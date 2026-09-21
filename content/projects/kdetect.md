---
title: "kdetect — Catching a Linux Rootkit in a Contradiction"
date: 2026-09-07
author: "Angus Dawson"
tags: ["linux","rootkit","detection-engineering","kernel","python","procfs","diamorphine","dfir","tooling"]
categories: ["Projects"]
difficulty: "Advanced"
platform: "Debian 12 lab VM"
featured: true
featured_weight: 3
summary: "A rootkit hides by lying to whoever asks, so asking /proc twice gets you the same lie twice. kdetect asks through channels a rootkit has to subvert separately and treats their disagreement as the finding. This is how it works, how I validated it against a real rootkit, and the false positives that nearly shipped."
---

> **Project note**
> kdetect is a Linux kernel rootkit detector I wrote in Python. Everything here
> ran on a disposable Debian 12 VM I built from a verified installer, on a
> host-only segment, with the rootkit source deliberately kept out of the
> repository. Source: [github.com/basil9099/kdetect](https://github.com/basil9099/kdetect).

---

## TL;DR

A rootkit's whole job is to answer questions dishonestly. Anything that asks
`/proc` once and believes the answer is asking the compromised party for a
character reference. kdetect asks the same question through several channels
that a rootkit has to subvert *separately*, records every answer, and reports
where they disagree. The disagreement is the finding.

Detection turned out to be the easy half. The hard half was proving the
disagreements meant something, because a clean Debian box disagrees with itself
constantly for reasons that have nothing to do with rootkits. My first naive
comparison reported about ninety hidden processes on a machine with nothing
loaded on it.

---

## The problem with asking /proc

Most process hiding on Linux happens at the `/proc` readdir path. A rootkit hooks
the directory listing, drops its own entries, and every tool that walks `/proc`
inherits the lie. `ps`, `top`, `htop` and your EDR agent all read the same
directory.

So running `ps` twice proves nothing. Running two different tools proves nothing
either, if both are built on the same listing. To catch the lie you need a
question the rootkit answered somewhere else, and then you need the two answers
side by side.

## Cross-view detection

The idea is old. For a hidden process, kdetect asks four ways:

- **readdir** — walk `/proc` and record what the listing offers. This is the
  channel under attack.
- **syscall sweep** — call `kill(pid, 0)` for every possible task id. That
  answers from the kernel's task table, not from a directory.
- **direct read** — read `/proc/<tid>/status` by path. `/proc/<pid>` answers even
  when readdir refuses to list it, and it returns identity as well as existence.
- **socket ownership** — attribute open sockets back to owning pids through
  `/proc/<pid>/fd`.

A pid confirmed by the sweep, by a direct read, and by a socket it owns, but
absent from the listing, is hidden. Modules work the same shape: `/proc/modules`
is the listing, and kernel taint bits, unaccounted vmalloc regions, and ftrace
hook ownership are three channels a module has to suppress on its own.

Two design rules fell out of this and shaped everything else. Snapshots hold
evidence, never conclusions. And disagreement between channels stays
representable; nothing is resolved at capture time. If two collectors contradict
each other, both answers get written down and the analysis stage decides later.

## Building a lab you can make claims about

Every finding kdetect produces is a claim about how a machine differs from clean.
That claim is worth exactly as much as your knowledge of what clean looked like.

I started phase 1 on a prebuilt Debian image off the internet. That was fine
while nothing was being detected, but it went into the limitations log on day
one as L1: a third-party image with documented default credentials and
passwordless sudo cannot tell you what uncompromised looks like. Before writing
a single detector I rebuilt the VM from `debian-12.12.0-amd64-netinst.iso`,
checked the hash and then the OpenPGP signature on the hash file, and recorded
the result in the repo.

```bash
gpg --keyring /usr/share/keyrings/debian-role-keys.gpg --verify SHA256SUMS.sign SHA256SUMS
```

A `Good signature` line is the difference between trusting a certificate
authority and trusting Debian. Netinst was deliberate: it installs only what you
ask for, so the machine stays small enough that you can plausibly account for
every package on it.

The rest of the lab discipline is unglamorous and non-negotiable. Snapshot before
loading anything live. Switch the adapter to host-only *before* the rootkit
loads, not after. Commit and push everything you want to keep while still on the
clean snapshot, then never push again until you're back on it. The VM holds a
deploy key, and a compromised machine is a bad place to be authenticating from.
Rootkit source and binaries are gitignored and never committed; the only kernel
module in the repository is my own.

## Step 0: measure the clean machine first

Before designing the comparison logic for each phase, I ran an evidence pass on
the clean VM whose only purpose was to find out how far the channels disagree
when nothing is wrong. Every clean-machine disagreement is a false positive the
detector will have to explain away, and I would much rather find them before the
detector exists than after.

That pass is committed under `docs/step0*/`.

### Ninety hidden processes on a machine with no rootkit

`/proc` lists about 136 entries on the idle lab VM. The `kill(pid, 0)` sweep
finds about 226 live task ids. A straight diff of those two sets reports ninety
hidden processes.

None of them are hidden. `/proc` lists thread group leaders; the sweep hits every
task, threads included. The fix is one line of intent — fold each task into its
leader via `Tgid` before comparing — but shipping a detector that cries wolf
ninety times on a clean box would have been a much slower thing to discover from
the other end.

The same pass settled a timing question. Capture runs procfs → sweep → procfs,
in that order, so a process that starts or exits mid-capture shows up as a
channel disagreement that resolves cleanly against the second walk. Idle,
the two walks and the sweep agree on the ninety thread ids and nothing else.
Under deliberate process churn, only the churning processes differ, and every one
of them resolves to a listed leader. That sandwich separates "the system moved"
from "something is hiding", which are otherwise the same shape of evidence.

### Two more listings that disagree for boring reasons

`/sys/module` lists 136 entries against `/proc/modules`' 72. Built-in kernel code
registers a sysfs directory without being a loadable module at all, so the gap is
enormous and entirely legitimate. The discriminator is `initstate`.

And `/proc/kallsyms` carries bracketed owner tags that look like module names but
aren't. `[bpf]` shows up with no module behind it.

Neither is exciting, and both would have produced confident nonsense.

### The detector I deleted

The one I'm most pleased about is a detector that worked and got removed anyway.

Phase 4a shipped a `hidden_socket` signal: a file descriptor a process holds that
appears in none of the `/proc/net` tables, which sounds exactly like a connection
hidden from those tables. The clean-host calibration disproved it in a single
run. Two `hidden_connection` findings on a machine with nothing loaded on it:

![kdetect analyze on a clean capture reporting two LOW hidden_connection findings, socket inodes 15229 and 20696, seen by hidden_socket and denied by the /proc/net tables](/images/projects/kdetect/clean_host_false_positives.png)

Tracing both inodes back through `/proc/<pid>/fd` named the culprits, and neither
was a rootkit:

![Shell loop resolving inode 15229 to /proc/393/fd/8 owned by vmtoolsd, and inode 20696 to /proc/659/fd/5 owned by dbus-daemon](/images/projects/kdetect/fp_traced_to_vmtoolsd_dbus.png)

`vmtoolsd`'s `AF_VSOCK` link to the VMware host, and a `dbus-daemon` socket.
Several real socket families have no `/proc/net` table at all, and a file
descriptor carries no address family you could use to tell the difference:

![Checking dbus fd5's inode 20696 against /proc/net/unix and getting NOT in unix table, some non-/proc/net family](/images/projects/kdetect/dbus_socket_not_in_unix_table.png)

There is no `/proc/net/vsock` to add. "In no table" and "hidden" are
indistinguishable under a `/proc`-only design.

So the signal came out, along with the finding kind that depended on it. What
stayed is the direction that is sound: a socket that *is* in a table, owned by a
pid that readdir won't list, which is strong evidence of a hidden process.
Detecting a genuinely hidden connection needs `sock_diag` netlink — how `ss`
actually works — and that's deferred rather than faked.

![The same clean capture re-analysed after the signal was removed, reporting findings: none](/images/projects/kdetect/clean_after_signal_removed.png)

Tuning a threshold would have kept the feature and hidden the problem, so
deleting it was the honest option.

## Proving it on a real rootkit

Calibration tells you the false positive rate. It doesn't tell you the thing
works. For that I ran it against Diamorphine, a well-known Linux LKM rootkit, on
Debian 12 with kernel 6.1.0-52. Its hidden module was caught three independent
ways:

![kdetect analyze on the infected Diamorphine capture, reporting three HIGH findings: module_taint_mismatch on taint bit 12, unexplained_module_region with one unaccounted region, and ftrace_orphan_module naming diamorphine. Exit code 3](/images/projects/kdetect/diamorphine_detected.png)

Taint bit 12 set, one vmalloc region more than `/proc/modules` accounts for, and
an ftrace record still carrying the module's name after it unlinked itself.
Diamorphine had removed itself from the listing and left its fingerprints on
three channels it didn't think to clean.

Real rootkits are awkward ground truth, though. You can't commit one, and you
can't ask a reader to trust a screenshot. So I also wrote a small kernel module
of my own, `kmod/kdetect_hooktest.c`, which hides itself from `/proc/modules` and
installs an ftrace hook on a syscall. It's GPL-2.0, it's committed, it builds,
and it's the ground truth for hook detection that anyone can reproduce.

![dmesg after loading kdetect_hooktest: loading out-of-tree module taints kernel, module verification failed, hooked __x64_sys_newuname, hidden from module list](/images/projects/kdetect/hooktest_dmesg.png)

Because I wrote it, I can run the control case that a real rootkit won't give
you. Loaded but *not* hiding, it shows up in `lsmod` and kdetect says nothing:

![kdetect analyze with kdetect_hooktest loaded and visible in lsmod, 73 modules listed, reporting findings: none](/images/projects/kdetect/hooktest_visible_no_findings.png)

Told to hide, the same module on the same boot starts contradicting the listing:

![kdetect analyze after the module hides itself: module_taint_mismatch on bits 12 and 13, unexplained_module_region, and unexpected_hook on __x64_sys_newuname](/images/projects/kdetect/hooktest_hidden_findings.png)

That pair is the test I trust most. The only variable between the two runs is
whether the module lies, so anything kdetect reports in the second run and not
the first is caused by the hiding rather than by the module merely existing.

Those findings are scored per signal, which is the phase 3a output. Phase 3b
composed them per suspect, which is why the same evidence now presents as the
single HIGH `hidden_module` further up rather than a MEDIUM, a MEDIUM and a
LOW.

## What it looks like

The repository ships real captures from the lab VM, so this runs with no VM and
no root:

```bash
kdetect analyze tests/fixtures/snapshots/infected-hooktest.json
```

```text
  procfs.modules   trust=LOW   status=OK   74 entities   0ms
                     listed=74
  kernel.module_evidence   trust=MEDIUM   status=OK   0 entities   93ms
                     ftrace_available=True  ftrace_module_count=70  load_module_regions=75  taint=12288
  kernel.hooks   trust=MEDIUM   status=OK   1 entities   71ms
                     enabled_functions_available=True  hooks=1  kallsyms_available=True  kprobes_available=True

findings:
  [HIGH]   hidden_module   module kdetect_hooktest
           seen by: taint, unexpected_hook, vmalloc_region
           denied by: procfs.modules listing
```

Three channels named the module and the listing denied it. Seventy-five module
regions in vmalloc against seventy-four listed, and taint bits 12 and 13 set with
no listed module wearing the marker.

`kdetect capture` needs a live `/proc` and so runs on Linux only. Analysis,
reporting and redaction work on the JSON anywhere, which means you can capture on
the suspect host and analyse somewhere you trust. Exit codes are scriptable: 0
means no findings, 3 means findings, and neither one indicates a crash.

## Confidence is a corroboration count

Every finding names both the channels that saw the thing and the channel that
denied it, and confidence is corroboration count scoped per suspect. One channel
is LOW. Two is MEDIUM. Three or more is HIGH. There is no tuning knob and no
model, and I can explain any score in a sentence.

The reporting layer concludes nothing of its own. It presents what the analysis
found, and every line traces back to a finding or a recorded fact. Indicators of
compromise are extracted separately, and only for things that travel: a module
name, a hooked syscall, a C2 endpoint. Pids and inodes are host-local, so they
stay as context. Handing someone a pid as an IOC gives them a number that can't
mean anything on their machine.

Baselines are ordinary snapshots plus a detached ed25519 signature, verified
before parsing.

## What it can't detect

The limitations document runs to 26 numbered entries, each traced to captured
evidence in the repo. The shape of them:

Cross-view finds inconsistency, not malice. A rootkit that patches every view
coherently, or one operating below the level kdetect can see, produces no
disagreement and therefore no finding. This is the load-bearing limitation and no
amount of extra channels removes it.

kdetect runs on the machine it's inspecting, parsing input that a
kernel-level attacker can influence. On-host signing bounds the problem without
solving it. Off-host verification is future work, and I'd rather say that than
imply the current design is tamper-proof.

Some evidence is simply gone. A hidden process's `exe` and `cmdline` can't be
recovered, because the collector that records them is the readdir path the
rootkit suppressed. A report identifies it by `comm`, `tgid` and the sockets it
owns, and says plainly that the rest is unavailable. That's a property of the
process being hidden, not a gap in the report.

Ten of the twelve detection methods in the original brief are implemented. One is
implemented as a constraint on what kdetect is allowed to read. One is planned.

## How it's put together

One rule shapes the whole codebase: only the Source layer touches the operating
system. Everything underneath it — parsers, collectors, detectors, scoring,
reporting — is pure, and receives its data as an argument rather than going and
fetching it.

{{< diagram src="kdetect-architecture.svg" caption="Capture writes evidence, analysis reads it. The two halves only ever meet through a snapshot file, so a capture taken on a compromised box in August can be re-analysed by a detector written in September." >}}

That is what makes the fixture seam real. A collector is handed a source:

```python
ProcfsProcessCollector().collect(LiveProcSource())
ProcfsProcessCollector().collect(FixtureProcSource(path))
```

There is no `if testing:` branch anywhere, so a fixture-driven test exercises the
identical code path as a live capture — which is the only reason the committed
Diamorphine capture works as a regression test instead of as a mock that agrees
with whatever I last wrote.

The fixture trees carry an `_errors.json` sidecar mapping each path to an errno,
because a directory of copied files can only replay the happy path, and every
false positive in this project came out of a failure path: the kernel thread with
no `exe`, the `EACCES` read, the process that vanished mid-scan. Those reads
raise, the same way they do on a real box.

## How it was built

Spec-first, in phases, with AI assistance, and the specs and implementation plans
are committed under `docs/superpowers/` if you want to check the working.

What made that productive was the step-0 habit described above: gather evidence
about the real system before designing anything, and trace every limitation to a
capture. A model will happily produce a detector that looks correct. Only the
clean machine can tell you it fires ninety times on nothing.

Both rootkits are pinned as committed fixtures with a test each, so a refactor
that breaks Diamorphine detection fails the suite:

![pytest running tests/unit/test_ground_truth.py with 9 tests passed, including test_infected_diamorphine_detects_hidden_module and test_clean_phase2_has_zero_findings](/images/projects/kdetect/ground_truth_tests.png)

The clean captures are in there too. A detector that finds nothing is useless,
but a detector that finds something on a clean box is worse, so both directions
are asserted.

One more guardrail: Python 3.11 is the floor, enforced by a test, because a
3.12-only construct once passed the entire suite on my 3.12 workstation and
broke on import on the 3.11 lab VM. Environment drift between where you write
code and where you run it is a bug class, so I made it a test rather than a
habit.

## Links

- [**kdetect on GitHub**](https://github.com/basil9099/kdetect) — MIT, except the
  kernel module, which has to be GPL-2.0 to use GPL-only kernel symbols.
- [`docs/architecture.md`](https://github.com/basil9099/kdetect/blob/main/docs/architecture.md)
  — how it's put together, and the principles behind it.
- [`docs/detection-methods.md`](https://github.com/basil9099/kdetect/blob/main/docs/detection-methods.md)
  — each detection method, individually.
- [`docs/limitations.md`](https://github.com/basil9099/kdetect/blob/main/docs/limitations.md)
  — all 26, with the evidence.
- [`docs/threat-model.md`](https://github.com/basil9099/kdetect/blob/main/docs/threat-model.md)
  — who it's defending against.

---

## Scope and safety

Live rootkit work belongs on a disposable VM with a snapshot to revert to, never
on a workstation. Rootkit source and binaries are excluded from the repository
deliberately. `.gitignore` drops all of `lab/targets/`, and the only kernel
module committed is kdetect's own benign test module. Nothing here touched a
system I don't own.
