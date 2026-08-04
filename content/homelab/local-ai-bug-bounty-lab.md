---
title: "Building a Local-AI Bug Bounty Lab — and Where the AI Lied to Me"
date: 2026-08-04
author: "Basil9099"
tags: ["homelab","ai","ollama","qwen","bug-bounty","recon","classicpress","kali","vmware"]
categories: ["Homelab"]
series: ["Homelab Labs"]
difficulty: "Intermediate"
platform: "Local Homelab"
summary: "Wiring an AI-driven recon tool to a self-hosted LLM on my own GPU, driving it from a Kali attack VM against a ClassicPress target on an isolated network — cross-host inference, a VRAM wall, a silent clean run against the wrong target, and the recurring lesson that a local model is a lead-generator, not an oracle."
---

> **Homelab note**
> This post documents an AI-assisted bug bounty lab built entirely on hardware I
> own, against a target I built myself, on an isolated network. The interesting
> part isn't "AI finds bugs" — it's the engineering judgment, and the places the
> model would have misled me if I'd trusted it.

*Running an AI-driven recon tool on a self-hosted LLM, on isolated hardware,
against a target I built myself — and treating the model as a suspect, not an
oracle.*

---

## TL;DR

I wired up an AI-assisted bug bounty tool (BugHunter) to a **local** LLM
(Qwen 3 on Ollama) running on my own GPU, connected it from a Kali attack VM,
and pointed it at a self-hosted ClassicPress target on an isolated network. The
interesting part wasn't "AI finds bugs" — it was everything that broke on the
way, and the recurring lesson that a local model is a fast, tireless
*lead-generator* whose output you verify by hand, not a source of truth. This
writeup is about the engineering judgment, not a magic-button demo.

---

## Why local AI at all

The default for AI-assisted security tooling is to pipe everything to a cloud
model. For a learning lab I deliberately went the other way, for three reasons:

- **Privacy / control.** Recon output and target details never leave my network.
- **Cost.** Agentic loops burn tokens; local inference is free after the download.
- **Staying in the loop.** This is the real one. As someone working toward OSCP,
  the *last* thing I want is a black box that hands me findings I don't
  understand. A local model with obvious limitations forces me to review every
  step — which is the skill I'm actually trying to build.

The honest tradeoff up front: a local ~14B model is meaningfully weaker than a
frontier cloud model at multi-step agentic reasoning, and on consumer hardware
you're constrained on context. I wasn't chasing state-of-the-art output. I was
building a workflow I could reason about end to end.

---

## The architecture

Three machines, fully isolated on a VMware NAT network so nothing touches my
real LAN or the internet-facing world:

```text
  Windows host (RTX 4070, 12 GB) ── Ollama :11434 (Qwen 3, on the GPU)
        │  VMware NAT (VMnet8)
        ├── Kali VM ...... ATTACKER  (BugHunter, wpscan, nuclei)
        └── Ubuntu 24.04 .. TARGET   (LAMP + ClassicPress 2.7.0)
```

Inference runs on the Windows GPU; the Kali box just orchestrates tools and
talks to Ollama over the network. No GPU passthrough needed. Attacker and target
are separate machines on purpose — you never test from the same box you're
attacking, and a deliberately-vulnerable target should never be reachable from
anywhere it shouldn't be.

![Ollama on the Windows host listing the installed Qwen 3 models](/images/homelab/local-ai-bug-bounty-lab/ollama_list.png)

---

## The build — and what actually broke

I'm skipping the parts that went to plan. The value is in the friction.

### 1. Getting cross-host inference working

Ollama binds to `127.0.0.1` by default, so out of the box the Kali VM couldn't
reach it. The fix is to set `OLLAMA_HOST=0.0.0.0:11434` and restart the service —
but "restart" is where people (me) get caught: the env var only applies to newly
started processes, and Ollama's server is already running in the background from
the tray. You have to *fully quit and relaunch it*, not just close a terminal.

The verification step taught me to read `netstat` properly:

```text
TCP   127.0.0.1:11434   0.0.0.0:0   LISTENING
      ^ Local Address   ^ Foreign Address (always 0.0.0.0 for a listener — ignore it)
```

The `0.0.0.0` you *want* has to appear in the **Local** column on the left. I
initially misread the Foreign-address placeholder as success. After the proper
restart it read `0.0.0.0:11434` on the left, and Kali could reach it.

I scoped the Windows firewall rule to the VM subnet only (`remoteip=<nat-subnet>/24`),
not `Any` — the Ollama endpoint has **no authentication**, so an open port there
is a genuine exposure, not a lab convenience.

![netstat before: the listener bound to 127.0.0.1:11434](/images/homelab/local-ai-bug-bounty-lab/netstat_before.webp)

![netstat after the proper restart: the listener bound to 0.0.0.0:11434 in the Local column](/images/homelab/local-ai-bug-bounty-lab/netstat_after.png)

**Lesson:** know your VM networking, and don't trust a config change until you've
verified the actual listening state — not the command's exit code.

### 2. Reading the tool's source instead of guessing

BugHunter auto-selects a model and sets a context window internally. Rather than
treat that as a black box, I read the source. Two constants mattered:

- A `MODEL_PRIORITY` list that picks the highest-ranked *installed* model.
- A hardcoded `MAX_CTX` controlling the context window sent to Ollama.

Knowing these existed is what let me fix the next problem deliberately instead of
flailing. It's a small thing, but "read the tool before you fight it" saved me
hours.

**Lesson:** tools are just code. When behaviour surprises you, the answer is
usually in the source, not in a forum thread.

### 3. The VRAM wall — the one I'm proudest of

First real run, I checked `ollama ps` mid-execution:

```text
NAME        SIZE   PROCESSOR      CONTEXT
qwen3:14b   14 GB  31%/69% CPU/GPU  32768
```

`31%/69% CPU/GPU` means the model wasn't fully on the GPU — nearly a third of it
had spilled onto the CPU, which craters throughput. The cause was the `CONTEXT`
value: the tool requested a 32K window, and on a 12 GB card that doesn't fit
alongside a 9.3 GB 14B model.

The napkin math: a 32K KV cache for that model is on the order of ~5 GB. Add the
9.3 GB of weights and you're well past the ~11 GB of usable VRAM, so Ollama
offloads layers to system RAM. That's the spillover.

The interesting decision was the fix. The obvious move — shrink the context to
8K so the 14B fits — is wrong for *this* workload. BugHunter's analysis phase
works by feeding the entire recon dump into the model to reason over. Cutting the
window to 8K means the model literally can't see half the data. So the better
trade was to drop to the **8B** model, which holds the full 32K window entirely
on the GPU:

- **14B @ 8K context** → smarter model, but reasoning over half the evidence.
- **8B @ 32K context** → slightly less capable model, sees *all* the evidence,
  and runs `100% GPU`.

For "read this pile of recon output and reason about it," context beat raw
capability. I made the tool select the 8B by adjusting its model-priority list,
kept the full context, and re-checked `ollama ps`:

```text
qwen3:8b   ~6 GB   100% GPU   32768
```

![ollama ps showing qwen3:14b split 31%/69% CPU/GPU at a 32K context](/images/homelab/local-ai-bug-bounty-lab/cpu-gpu_split_qwen.webp)

![ollama ps showing qwen3:8b running 100% GPU at the full 32K context](/images/homelab/local-ai-bug-bounty-lab/gpu-100.png)

**Lesson:** measure, don't assume. And the "best" model isn't the biggest one —
it's the one that fits the workload's real constraint, which here was context,
not parameters.

### 4. A clean pipeline pointed at nothing

With the model behaving, I ran the hunt — the brain came online, connected to
Ollama, and kicked off recon analysis against the target:

![BugHunter connecting to Ollama and starting recon analysis against the target with qwen3:8b](/images/homelab/local-ai-bug-bounty-lab/bughunter_output-ai-model.png)

And got:

```text
No findings — nothing to interpret.   (Model: qwen3:8b)
```

![The BugHunter interpretation output reporting no findings](/images/homelab/local-ai-bug-bounty-lab/no-findings.png)

Everything *worked*. That was the trap. BugHunter is built for internet-facing
domains and probes the web **root**; my ClassicPress install lived at a
subdirectory, so the tool had dutifully analysed an empty Apache default page and
correctly reported nothing. A green, error-free run that tells you absolutely
nothing looks a lot like success if you're not paying attention.

Moving the app to the web root surfaced a second bug — the site 404'd. The Apache
error log was unambiguous:

```text
AH00112: Warning: DocumentRoot [/var/www/html/classicpress/classicpress] does not exist
```

A doubled path — I'd run a `sed` substitution twice. Set it explicitly, reload,
`curl -I` returns `200`, site loads.

![curl -I returning HTTP/1.1 404 Not Found from the target](/images/homelab/local-ai-bug-bounty-lab/404.webp)

![curl -I returning HTTP/1.1 200 OK, with the wp-json Link header confirming the CMS is serving from the web root](/images/homelab/local-ai-bug-bounty-lab/200-lamp.png)

**Lesson:** a successful run against the wrong target is worse than an error,
because it's silent. Always confirm the tool is looking at what you think it is.
And read the logs — they usually just tell you.

---

## Where the AI helped, and where it lied

This is the part I care about most, because the honest version is more useful
than the hype.

**Where a local model genuinely helped:**

- Orchestrating a multi-tool recon pipeline and summarising the combined output
  into something readable.
- Drafting — notes, structure, first-pass write-ups — where I'm the editor.
- Bounded, human-in-the-loop tasks where I can immediately sanity-check it.

**Where it lied, or would have if I'd trusted it:**

- **Confident false positives.** The triage/validation step will wave things
  through as "findings" that don't hold up. Treated as a verdict, that's a
  wasted afternoon or, worse, garbage in a report.
- **Silent empty results.** As above — "nothing to interpret" read as "target is
  clean" would have been completely wrong.
- **Degraded reliability under load.** Small models get less consistent over long
  agentic loops — exactly where you're most tempted to stop watching.

The through-line of the whole build: **the model is a lead-generator, not an
oracle.** Every finding it surfaces is a hypothesis I reproduce by hand before
it's real. That's not a limitation to apologise for — on an OSCP track it's the
entire point. The tool that forces me to verify is teaching me more than the one
that doesn't.

---

## What I'd tell someone building this

- Run inference where the GPU is; orchestrate from your attack box; keep them
  separate machines on an isolated network.
- Verify listening state and connectivity explicitly — don't trust exit codes.
- Read the tool's source. Model choice and context window are usually just
  constants you can tune.
- On limited VRAM, context can matter more than model size. Check `ollama ps`
  during runs, not after.
- A clean run against the wrong target is a silent failure. Confirm scope first.
- Treat every AI finding as unverified until you reproduce it by hand.

---

## Scope & ethics

Everything here ran against a target I built, on an isolated network I own. No
live systems, no third-party programs, no real client data. Automated,
"autonomous" security tooling acts without pausing to ask — so it only ever gets
pointed at in-scope bounty targets or gear I control. Knowing what *not* to point
it at is part of the skill set.

---

## Tools & credits

- **BugHunter** by shuvonsec — the AI-driven recon/hunting framework.
- **Ollama** + **Qwen 3** (8B / 14B) — local inference.
- **ClassicPress 2.7.0** — WordPress-lineage CMS, used as a self-hosted target.
- **wpscan**, **nuclei** — the purpose-built CMS tooling I lean on for the actual
  hunting (a WordPress-fork target is their home turf, path and all).
- **VMware Workstation** — the isolated lab.

*Next up: enumerating the CMS properly with wpscan/nuclei — including an
installed plugin I spotted on the target, since plugin code is where the real
attack surface on a WordPress-lineage CMS tends to live — and turning raw
findings into a repeatable manual methodology.*
