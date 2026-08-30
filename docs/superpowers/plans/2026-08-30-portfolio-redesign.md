# Portfolio Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure basil9099.github.io so a non-technical screener can identify who Angus is and how to contact him within 30 seconds, without losing the technical depth or terminal character that makes the site credible to security readers.

**Architecture:** A layered homepage that sequences from a screener-readable hero into the existing writeup listings. The terminal aesthetic is demoted from page-wide wallpaper to a scoped accent. Palette moves to a neutral slate ground with working light and dark themes, body copy moves from monospace to sans-serif, and the missing About page, search page, and normalised post metadata are added.

**Tech Stack:** Hugo 0.165.0 extended, PaperMod theme (git submodule), vanilla CSS in `assets/css/extended/`, GitHub Actions to GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-08-30-portfolio-redesign-design.md`

## Global Constraints

These apply to every task. Copy rules are non-negotiable and appear in the final verification.

- **Hugo version:** 0.165.0 extended, locally and in CI. Local binary lives at `C:\Users\angus\AppData\Local\Microsoft\WinGet\Packages\Hugo.Hugo.Extended_Microsoft.Winget.Source_8wekyb3d8bbwe\hugo.exe` and is not on `PATH` in older shells.
- **No copy may claim professional penetration testing experience.** Angus has none yet. Lab and CTF work is labelled as self-directed.
- **No copy may state a job title Angus does not hold.** The hero leads with capability, not title.
- **No copy may mention certification costs** or why OSCP is deferred.
- **No copy may contain a personal email address.** LinkedIn is the sole contact route.
- **No copy may name the current employer.** Refer to it as "financial services" only.
- **Contact URLs:** LinkedIn `https://www.linkedin.com/in/angus-dawson-92b035249/`, GitHub `https://github.com/basil9099`.
- **Text contrast must meet WCAG AA in both themes.**
- **Existing permalinks must not change.** No content file may be renamed or moved.
- **Do not rewrite the body content of any writeup.** Frontmatter and summaries only.
- **Work on the `redesign` branch.** Never switch branches, and never touch `main` — it auto-deploys on push.
- **Angus owns every commit and push.** No task may run `git commit` or `git push`. Stage changes with `git add`, report the diff, and stop. Each task supplies a suggested commit message for him to use or ignore.
- **Pro Labs and active machines are load-bearing claims.** Dante and P.O.O. are completed HTB Pro Labs; machines are solved while active and published only after retirement. Both are accurate and may be stated plainly.

---

### Task 1: Verification harness

Build the assertion script first, so every later task has an objective pass/fail. The assertions below describe the *finished* site, so most fail right now — that is the point.

**Files:**
- Create: `scripts/verify-site.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/verify-site.sh`, runnable as `bash scripts/verify-site.sh`. Exits 0 when all assertions pass, 1 otherwise. Every later task re-runs this.

- [ ] **Step 1: Write the verification script**

```bash
#!/usr/bin/env bash
# Builds the site and asserts on rendered output.
set -uo pipefail

HUGO="${HUGO_BIN:-hugo}"
if ! command -v "$HUGO" >/dev/null 2>&1; then
  HUGO="/c/Users/angus/AppData/Local/Microsoft/WinGet/Packages/Hugo.Hugo.Extended_Microsoft.Winget.Source_8wekyb3d8bbwe/hugo.exe"
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "== building =="
if ! "$HUGO" --minify --destination "$OUT" >/dev/null 2>&1; then
  echo "FAIL: hugo build errored"
  "$HUGO" --minify --destination "$OUT" 2>&1 | tail -20
  exit 1
fi

PASS=0
FAIL=0

check() { # check <description> <0-if-ok>
  if [ "$2" -eq 0 ]; then
    echo "  ok   - $1"; PASS=$((PASS+1))
  else
    echo "  FAIL - $1"; FAIL=$((FAIL+1))
  fi
}

present()  { grep -rqF "$1" "$OUT" >/dev/null 2>&1; }
absent()   { ! grep -rqF "$1" "$OUT" >/dev/null 2>&1; }

echo "== pages exist =="
check "about page renders"            "$([ -f "$OUT/about/index.html" ]; echo $?)"
check "search page renders"           "$([ -f "$OUT/search/index.html" ]; echo $?)"
check "search index emitted"          "$([ -f "$OUT/index.json" ]; echo $?)"

echo "== contact and identity =="
check "LinkedIn URL present"          "$(present 'linkedin.com/in/angus-dawson-92b035249'; echo $?)"
check "GitHub URL present"            "$(present 'github.com/basil9099'; echo $?)"
check "real name on homepage"         "$(grep -qF 'Angus Dawson' "$OUT/index.html"; echo $?)"

echo "== copy rules (spec: deliberate omissions) =="
MAILTO_HITS="$(grep -rhoIE 'mailto:[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+' "$OUT" 2>/dev/null | grep -viE '\.local$')"
check "no real-domain mailto link"    "$([ -z "$MAILTO_HITS" ]; echo $?)"
check "no personal-domain email"      "$(! grep -rqIiE '[a-z0-9._%+-]+@(hotmail|gmail|outlook|yahoo|icloud)\.[a-z]{2,}' "$OUT"; echo $?)"
check "no cert-cost language"         "$(! grep -rqiE 'financial reach|too expensive|afford' "$OUT"; echo $?)"
check "no 'security learner' framing" "$(absent 'security learner'; echo $?)"
check "no 'aspiring' framing"         "$(! grep -rqi 'aspiring' "$OUT"; echo $?)"

echo "== effects removed =="
check "no scanline overlay"           "$(absent 'repeating-linear-gradient'; echo $?)"
check "no injected ## heading prefix" "$(! grep -rqE 'content: ?"#{2,3} ?"' "$OUT" >/dev/null 2>&1; echo $?)"

echo "== metadata consistency =="
# Capital-B 'Basil9099' only ever appears as a byline; the GitHub URL is lowercase.
check "no Basil9099 byline"           "$(absent 'Basil9099'; echo $?)"
check "optimum has a real summary"    "$(! grep -qF 'I started with a straightforward service scan' "$OUT/index.html"; echo $?)"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Make it executable and run it to confirm it fails**

```bash
chmod +x scripts/verify-site.sh
bash scripts/verify-site.sh
```

Expected: build succeeds, then a majority of assertions report `FAIL` — specifically the about page, search page, LinkedIn URL, real name, `security learner`, the scanline, the `##` prefix, the `Basil9099` byline, and the Optimum summary. `passed: 4 failed: 10` or similar. A non-zero exit here is correct.

- [ ] **Step 3: Add build output to .gitignore**

Append to `.gitignore`:

```
# Verification build output
/tmp-verify/
```

- [ ] **Step 4: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add scripts/verify-site.sh .gitignore
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Add rendered-output verification script

Asserts on Hugo's generated HTML rather than on source, so the copy
rules from the spec (no personal email, no employer name, no implied
professional experience) are enforced against what actually ships.
```

---

### Task 2: Normalise post metadata and summaries

**Files:**
- Modify: `content/ctf/administrator-htb.md`, `content/ctf/blue-htb.md`, `content/ctf/cap-htb.md`, `content/ctf/optimum-htb.md`, `content/ctf/tombwatcher-htb.md`, `content/ctf/wifinetic-htb.md`
- Modify: `content/homelab/goad-light-setup.md`, `content/homelab/local-ai-bug-bounty-lab.md`, `content/homelab/phishing_simulation.md`, `content/homelab/splunk_install+bruteforce_test.md`, `content/homelab/windows-ad-lab.md`, `content/homelab/windows_pentest.md`
- Modify: `content/cheats/pentesting-commands.md`

**Interfaces:**
- Consumes: nothing.
- Produces: every post carries `author: "Angus Dawson"`; every CTF and homelab post carries `difficulty`, `platform`, and `os`; three posts carry `featured: true`. Task 6 selects featured posts with `where site.RegularPages "Params.featured" true`. Task 8 styles the difficulty vocabulary defined here.

**Difficulty vocabulary** (two distinct scales, per spec):
- CTF posts use the Hack The Box scale: `Easy`, `Medium`, `Hard`, `Insane`.
- Homelab posts use: `Easy`, `Intermediate`, `Advanced`.

**Categories** collapse to exactly three: `CTF Writeups`, `Homelab`, `Cheat Sheets`. Platform and tech detail stays in `tags`.

- [ ] **Step 1: Verify the HTB difficulty ratings before writing them**

Do not publish a difficulty you have not confirmed. Open each machine's page on Hack The Box and confirm the official rating and OS. Expected values, to be confirmed rather than assumed:

| Post | Difficulty | OS |
|---|---|---|
| `blue-htb.md` | Easy | Windows |
| `cap-htb.md` | Easy | Linux |
| `optimum-htb.md` | Easy | Windows |
| `wifinetic-htb.md` | Easy | Linux |
| `administrator-htb.md` | Medium | Windows |
| `tombwatcher-htb.md` | Medium | Windows |

A wrong difficulty on your own writeup is the kind of detail an interviewer notices. If a rating differs from the table, use the real one.

- [ ] **Step 2: Set author on every post**

Every file listed above gets `author: "Angus Dawson"` in frontmatter. Replace `author: "Basil9099"` where present; add the line where absent. Do not add an author to `content/*/_index.md` section pages.

- [ ] **Step 3: Add difficulty, platform, and os to CTF posts**

For each CTF post, ensure these three keys exist with the confirmed values from Step 1. `blue-htb.md` already has `difficulty` and `platform` and needs only `os`. Example for `administrator-htb.md`:

```yaml
difficulty: "Medium"
platform: "Hack The Box"
os: "Windows"
```

- [ ] **Step 4: Add difficulty and platform to homelab posts missing them**

`phishing_simulation.md`, `splunk_install+bruteforce_test.md`, and `windows-ad-lab.md` currently have neither. Add:

```yaml
platform: "Local Homelab"
difficulty: "Intermediate"
```

Exception: `windows-ad-lab.md` is an introductory domain build, so use `difficulty: "Easy"` for that one. If Angus disagrees with any of these three ratings on review, his call wins — they describe his own labs.

- [ ] **Step 5: Unify categories**

Set `categories: ["CTF Writeups"]` on all six CTF posts, `categories: ["Homelab"]` on all six homelab posts, and `categories: ["Cheat Sheets"]` on `pentesting-commands.md`. Delete the `["HTB", "writeup", "pentest"]` array on `optimum-htb.md` — that detail already lives in its `tags`.

- [ ] **Step 6: Give optimum-htb.md a summary**

This is the one visibly broken card on the homepage. Add to its frontmatter:

```yaml
summary: "A Windows box that falls to a known file-server vulnerability, then to a kernel-level privilege escalation. Rejetto HFS 2.3 RCE (CVE-2014-6287) for a foothold, then local exploit enumeration to SYSTEM."
```

- [ ] **Step 7: Add plain-English lead sentences to the four attack-chain summaries**

Keep every existing chain intact. Prepend one sentence that a non-specialist can follow. The chain stays for technical readers.

`tombwatcher-htb.md`:
```yaml
summary: "A Windows domain box where a chain of small misconfigurations adds up to full control, ending in an Active Directory certificate template flaw. Henry → targeted Kerberoast on Alfred → AddSelf to INFRASTRUCTURE → ReadGMSAPassword on ansible_dev$ → Sam → John → WinRM pivot → reanimate tombstoned cert_admin via John's GenericAll on OU=ADCS → ESC15 (CVE-2024-49019) on the WebServer template → Administrator."
```

`administrator-htb.md`:
```yaml
summary: "Mapping an Active Directory domain with BloodHound, then walking the permission chain it exposes from a low-privilege account to domain administrator. Olivia → BloodHound ACL chain (ForceChangePassword) → Benjamin → FTP .psafe3 → hashcat → password spray to Emily → targetedKerberoast on Ethan → DCSync Administrator."
```

`cap-htb.md`:
```yaml
summary: "A web app that leaks another user's traffic capture, and a Linux privilege feature left too permissive. IDOR → PCAP recovery of credentials → SSH user shell → Linux file capabilities (getcap) → root via python3.8 capability."
```

`wifinetic-htb.md`:
```yaml
summary: "An exposed backup gives up a reused password, and the box's own wireless hardware provides the route to root. Anonymous FTP → backup extraction → credential reuse (SSH) → local wireless enumeration → WPS PIN attack (reaver) → root via local escalation."
```

- [ ] **Step 8: Flag the three featured posts**

Add `featured: true` to exactly these three:
- `content/ctf/tombwatcher-htb.md`
- `content/homelab/goad-light-setup.md`
- `content/homelab/splunk_install+bruteforce_test.md`

- [ ] **Step 9: Run verification**

```bash
bash scripts/verify-site.sh
```

Expected: `no Basil9099 byline` and `optimum has a real summary` now pass. Others still fail. Build must succeed.

- [ ] **Step 10: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add content/
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Normalise post metadata and open summaries with plain English

Unifies author and categories, adds difficulty/platform/os so the writeup
info card renders on every post, and gives Optimum the summary it was
missing. Attack chains are kept intact with a lead sentence in front so a
non-specialist reader has a way in.
```

---

### Task 3: Palette, typography, and working light mode

The root cause of the broken light theme: `assets/css/extended/terminal.css:3` declares the dark palette on `:root, .dark`, so light mode never gets its own values. PaperMod expects `:root` = light, `.dark` = dark.

**Files:**
- Modify: `assets/css/extended/terminal.css:1-31` (the `:root, .dark` block and the `html, body` rule)
- Modify: `layouts/partials/extend_head.html`
- Modify: `config.yaml`

**Interfaces:**
- Consumes: nothing.
- Produces: CSS custom properties `--accent`, `--accent-dim`, `--border-strong`, `--sans`, `--mono` available to all later tasks in both themes. Tasks 4, 6, and 8 consume these.

- [ ] **Step 1: Replace the token block**

Replace `assets/css/extended/terminal.css` lines 1–31 (from the opening comment through the closing brace of `html, body`) with:

```css
/* Neutral slate palette with green as a signal colour. */
/* PaperMod convention: :root is light, .dark is dark. */

:root {
    --theme: #ffffff;
    --entry: #f7f8fa;
    --code-block-bg: #f2f4f7;
    --code-bg: #f2f4f7;
    --border: #e2e5ea;
    --border-strong: #cdd3db;
    --tertiary: #e2e5ea;
    --primary: #14181f;
    --content: #333b47;
    --secondary: #5a6472;

    --accent: #12694a;
    --accent-dim: #0f5a3f;
    --accent-soft: rgba(18, 105, 74, 0.08);
    --warn: #8a5a00;
    --danger: #a32d2d;
    --insane: #6b3fa0;

    --mono: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo,
        Consolas, "Liberation Mono", monospace;
    --sans: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
        Helvetica, Arial, sans-serif;
}

.dark {
    --theme: #10141a;
    --entry: #161b23;
    --code-block-bg: #0c1016;
    --code-bg: #161b23;
    --border: #232a35;
    --border-strong: #303947;
    --tertiary: #232a35;
    --primary: #e6e9ee;
    --content: #c3cad5;
    --secondary: #8792a3;

    --accent: #3ddc84;
    --accent-dim: #2fae68;
    --accent-soft: rgba(61, 220, 132, 0.10);
    --warn: #ffcb6b;
    --danger: #ff6b6b;
    --insane: #c792ea;
}

html,
body {
    background: var(--theme);
    color: var(--content);
    font-family: var(--sans);
}

body {
    font-size: 16.5px;
    line-height: 1.7;
}

.post-content {
    font-family: var(--sans);
}

.post-content p {
    max-width: 68ch;
}
```

- [ ] **Step 2: Keep headings sans, metadata mono**

Find the `h1, h2, h3, h4, h5, h6` rule (around line 88 of the original file) and change `font-family: var(--mono);` to `font-family: var(--sans);`. Add after it:

```css
.post-meta,
.entry-footer,
.difficulty-pill,
.section-prompt,
.boxinfo,
.terminal-hero {
    font-family: var(--mono);
}
```

- [ ] **Step 3: Load Inter alongside JetBrains Mono**

In `layouts/partials/extend_head.html`, replace the single stylesheet link with:

```html
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500;600&display=swap">
```

Update the theme-color meta tag on the last line to `<meta name="theme-color" content="#10141a">`.

- [ ] **Step 4: Enable the theme toggle**

In `config.yaml`, remove the line `disableThemeToggle: true`. Leave `defaultTheme: dark` so returning technical visitors keep the dark view while the toggle now works.

- [ ] **Step 5: Build and inspect both themes**

```bash
bash scripts/verify-site.sh
```

Then preview and check light mode manually — this cannot be asserted by grep:

```bash
hugo server -D
```

Open `http://localhost:1313`, toggle the theme, and confirm: no white-on-white or black-on-black text anywhere, code blocks readable in both, difficulty pills visible in both (they will still look wrong in light — Task 8 fixes that), and nav and footer legible in both.

- [ ] **Step 6: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add assets/css/extended/terminal.css layouts/partials/extend_head.html config.yaml
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Fix light mode and move body copy to sans-serif

The dark palette was declared on ':root, .dark', so light mode never had
its own values and the toggle had to be disabled. Splits the palettes
along PaperMod's convention and re-enables the toggle. Body text moves to
Inter; monospace is now scoped to code, metadata, and terminal elements.
```

---

### Task 4: Remove the costume effects

**Files:**
- Modify: `assets/css/extended/terminal.css`

**Interfaces:**
- Consumes: tokens from Task 3.
- Produces: no new interfaces. Purely subtractive plus one replacement rule.

- [ ] **Step 1: Delete the scanline overlay**

Remove the entire `body::before` rule (the `radial-gradient` plus `repeating-linear-gradient` block, roughly lines 34–52 of the original file). Delete it outright — it has no replacement.

- [ ] **Step 2: Remove the injected heading prefixes**

Delete both the `.post-content h2::before` and `.post-content h3::before` rules. These render literal `##` and `###` before every heading, which reads as failed markdown and is announced by screen readers.

Keep the `.post-content h2, .post-content h3` rule but soften it:

```css
.post-content h2,
.post-content h3 {
    border-left: 3px solid var(--accent);
    padding-left: 12px;
    font-family: var(--sans);
}
```

- [ ] **Step 3: Remove the fake title bar from every code block**

Delete the `.post-content pre::before` and `.post-content pre::after` rules, and remove `padding-top: 32px !important;` and `position: relative;` from `.post-content pre`. The bar labels PowerShell, config files, and raw output all as `sh`, which is simply wrong.

- [ ] **Step 4: Remove the neon glow**

Remove every `box-shadow` that uses `--accent-glow` or a `0 0 Npx` glow:
- `#menu a:hover::after` — delete the `box-shadow` line, keep the underline.
- `.post-tags li:hover` — delete the `box-shadow` line, keep the border and colour change.
- `.pagination a:hover` — delete the `box-shadow` line.
- `.terminal-hero` — delete the `box-shadow` line.
- `.post-entry:hover` — replace the two-layer shadow with `box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);`

Then delete the now-unused `--accent-glow` variable if any definition remains.

- [ ] **Step 5: Run verification**

```bash
bash scripts/verify-site.sh
```

Expected: `no scanline overlay` and `no injected ## heading prefix` now pass.

- [ ] **Step 6: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add assets/css/extended/terminal.css
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Remove scanlines, neon glow, and injected heading prefixes

The '##' pseudo-elements read as markdown that failed to render and are
announced by screen readers. The per-code-block title bar mislabelled
PowerShell and output dumps as 'sh'. Glow and scanlines were costume.
```

---

### Task 5: Difficulty pills and boxinfo hardening

**Files:**
- Modify: `assets/css/extended/terminal.css` (the `.difficulty-pill` rules)
- Modify: `layouts/partials/boxinfo.html:8`

**Interfaces:**
- Consumes: the difficulty vocabulary from Task 2, tokens from Task 3.
- Produces: pill styling for six values across both themes.

- [ ] **Step 1: Replace the difficulty pill rules**

The current rules cover only `easy`/`medium`/`hard`/`insane` and only in dark. `goad-light-setup.md` sets `Intermediate`, which matches nothing and renders unstyled. Replace the whole pill block with:

```css
.difficulty-pill {
    display: inline-block;
    padding: 2px 10px;
    border-radius: 999px;
    font-family: var(--mono);
    font-size: 0.75em;
    font-weight: 500;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    border: 1px solid currentColor;
    white-space: nowrap;
}

.difficulty-pill.easy {
    color: var(--accent);
    background: var(--accent-soft);
}

.difficulty-pill.medium,
.difficulty-pill.intermediate {
    color: var(--warn);
    background: rgba(138, 90, 0, 0.08);
}

.difficulty-pill.hard,
.difficulty-pill.advanced {
    color: var(--danger);
    background: rgba(163, 45, 45, 0.08);
}

.difficulty-pill.insane {
    color: var(--insane);
    background: rgba(107, 63, 160, 0.08);
}

.dark .difficulty-pill.medium,
.dark .difficulty-pill.intermediate {
    background: rgba(255, 203, 107, 0.08);
}

.dark .difficulty-pill.hard,
.dark .difficulty-pill.advanced {
    background: rgba(255, 107, 107, 0.08);
}

.dark .difficulty-pill.insane {
    background: rgba(199, 146, 234, 0.08);
}
```

- [ ] **Step 2: Guard the unguarded series lookup**

`layouts/partials/boxinfo.html:8` reads `{{- $series := index .Params.series 0 }}`, which indexes into a value that is absent on most posts. It is tolerated by the current build but is fragile. Replace that line with:

```go-html-template
{{- $series := "" }}
{{- with .Params.series }}{{ $series = index . 0 }}{{ end }}
```

- [ ] **Step 3: Add an os row to the card**

Confirm the `os` row already exists in `boxinfo.html` (it does, around line 24). No change needed — Task 2 supplies the data that makes it render.

- [ ] **Step 4: Verify every post shows a card and a styled pill**

```bash
bash scripts/verify-site.sh
hugo server -D
```

Visit one CTF post and one homelab post in both themes. Confirm the info card renders with platform, difficulty, and os, and that the pill has colour — including on the GOAD post, which is the `Intermediate` case that was previously unstyled.

- [ ] **Step 5: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add assets/css/extended/terminal.css layouts/partials/boxinfo.html
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Style all six difficulty values in both themes

'Intermediate' matched no CSS rule and rendered unstyled. Adds the
homelab vocabulary alongside the HTB scale and gives every pill a light
theme variant. Also guards the unguarded series index in boxinfo.
```

---

### Task 6: Homepage restructure

**Files:**
- Modify: `layouts/index.html` (replace the hero section, lines 3–29; insert two new sections before the existing listings)
- Modify: `assets/css/extended/terminal.css` (append new section styles)

**Interfaces:**
- Consumes: `featured: true` from Task 2, tokens from Task 3, `.difficulty-pill` from Task 5.
- Produces: the finished homepage. No later task depends on its internals.

- [ ] **Step 1: Replace the terminal hero with the layered hero**

Replace the `<section class="terminal-hero">` block at `layouts/index.html:3-29` with:

```go-html-template
<section class="intro" aria-label="introduction">
  <h1 class="intro-name">Angus Dawson</h1>
  <p class="intro-role">
    Active Directory attack paths, lab building, and detection — working
    toward a first role in penetration testing.
  </p>
  <p class="intro-meta">Sydney, Australia · eJPT · Google Cybersecurity Certificate · studying CPTS</p>
  <div class="intro-links">
    <a class="btn btn-primary" href="/about/">About me</a>
    <a class="btn" href="https://www.linkedin.com/in/angus-dawson-92b035249/" rel="me noopener">LinkedIn</a>
    <a class="btn" href="https://github.com/basil9099" rel="me noopener">GitHub</a>
  </div>
</section>

<section class="capabilities" aria-label="what I work on">
  <div class="cap">
    <h2>Active Directory attack paths</h2>
    <p>Mapping how a foothold in a Windows domain becomes full control — across single machines and across multi-host networks in the Dante and P.O.O. Pro Labs.</p>
  </div>
  <div class="cap">
    <h2>Building the labs</h2>
    <p>Standing up the domains, servers, and networks I test against — including the parts that break, and what it took to fix them.</p>
  </div>
  <div class="cap">
    <h2>Detection engineering</h2>
    <p>Instrumenting those same labs with centralised logging, then checking whether the attacks I just ran actually show up.</p>
  </div>
</section>
```

- [ ] **Step 2: Add the featured work section**

Immediately after the capabilities section, before the `$ctf := where ...` assignments, insert:

```go-html-template
{{- $featured := where site.RegularPages "Params.featured" true }}
{{- if $featured }}
<section class="featured" aria-label="featured work">
  <h2 class="section-heading">Selected work</h2>
  <div class="featured-grid">
    {{- range first 3 $featured }}
    <a class="featured-card" href="{{ .Permalink }}">
      <h3>{{ .Title }}</h3>
      <p>{{ .Summary | plainify | htmlUnescape | truncate 150 }}</p>
      <span class="featured-meta">
        {{- with .Params.difficulty }}<span class="difficulty-pill {{ . | lower }}">{{ . }}</span>{{ end }}
        {{ .ReadingTime }} min read
      </span>
    </a>
    {{- end }}
  </div>
</section>
{{- end }}
```

- [ ] **Step 3: Retitle the listing headers**

The three `<h2 class="section-prompt">` headers stay — they are the terminal character the technical reader wants, now correctly placed below the professional layer. No change needed to their markup.

- [ ] **Step 4: Append the new section styles**

Add to the end of `assets/css/extended/terminal.css`:

```css
/* Homepage intro */
.intro {
    padding: 8px 0 28px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 32px;
}

.intro-name {
    font-size: 2.1rem;
    margin: 0 0 8px;
    color: var(--primary);
}

.intro-role {
    font-size: 1.1rem;
    color: var(--content);
    margin: 0 0 10px;
    max-width: 52ch;
    line-height: 1.55;
}

.intro-meta {
    font-family: var(--mono);
    font-size: 0.85rem;
    color: var(--secondary);
    margin: 0 0 20px;
}

.intro-links {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
}

.btn {
    display: inline-block;
    padding: 8px 16px;
    border: 1px solid var(--border-strong);
    border-radius: var(--radius);
    color: var(--primary);
    font-size: 0.9rem;
    transition: border-color 0.15s ease, color 0.15s ease;
}

.btn:hover {
    border-color: var(--accent);
    color: var(--accent);
}

.btn-primary {
    background: var(--accent-soft);
    border-color: var(--accent);
    color: var(--accent);
}

/* Capability strip */
.capabilities {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 22px;
    margin-bottom: 40px;
}

.cap h2 {
    font-size: 0.95rem;
    color: var(--accent);
    margin: 0 0 6px;
    border: none;
    padding: 0;
}

.cap p {
    font-size: 0.9rem;
    color: var(--secondary);
    margin: 0;
    line-height: 1.6;
}

/* Featured work */
.section-heading {
    font-size: 1.05rem;
    color: var(--primary);
    margin: 0 0 16px;
}

.featured-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 14px;
    margin-bottom: 44px;
}

.featured-card {
    display: block;
    padding: 16px 18px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: var(--entry);
    color: var(--content);
    transition: border-color 0.15s ease, transform 0.15s ease;
}

.featured-card:hover {
    border-color: var(--accent);
    transform: translateY(-2px);
}

.featured-card h3 {
    font-size: 0.98rem;
    margin: 0 0 8px;
    color: var(--primary);
    line-height: 1.4;
}

.featured-card p {
    font-size: 0.86rem;
    color: var(--secondary);
    margin: 0 0 12px;
    line-height: 1.6;
}

.featured-meta {
    font-family: var(--mono);
    font-size: 0.75rem;
    color: var(--secondary);
    display: flex;
    align-items: center;
    gap: 8px;
}

@media (max-width: 600px) {
    .intro-name { font-size: 1.7rem; }
    .intro-role { font-size: 1rem; }
}
```

- [ ] **Step 5: Remove the now-orphaned hero CSS**

Delete the `.terminal-hero`, `.terminal-hero-bar`, `.terminal-hero-body`, and `@keyframes blink` rules along with the `.traffic`, `.prompt`, `.user`, `.host`, `.cmd`, `.out`, and `.cursor` child rules. The hero they styled no longer exists.

- [ ] **Step 6: Run verification**

```bash
bash scripts/verify-site.sh
```

Expected: `real name on homepage`, `LinkedIn URL present`, `GitHub URL present`, and `no 'security learner' framing` now pass.

- [ ] **Step 7: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add layouts/index.html assets/css/extended/terminal.css
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Rebuild homepage to lead with identity, not jargon

The first screen was a simulated terminal calling Angus a 'security
learner', followed straight by attack-chain summaries. It now opens with
name, capability, location, and contact, then a plain-English capability
strip and three curated pieces, before the existing writeup listings.
```

---

### Task 7: About and search pages

**Files:**
- Create: `content/about.md`
- Create: `content/search.md`
- Modify: `config.yaml` (menu entries)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `/about/` and `/search/`, both linked from the main menu. Task 6's hero already links to `/about/`.

- [ ] **Step 1: Write the About page**

This is draft copy. It follows the section order and the omissions in the spec. Angus reviews and edits the wording before merge — the facts are correct, the voice is his to adjust.

Create `content/about.md`:

```markdown
---
title: "About"
layout: "single"
url: "/about/"
summary: "Angus Dawson — working toward a first role in penetration testing, based in Sydney."
ShowToc: false
ShowReadingTime: false
ShowBreadCrumbs: false
hideMeta: true
---

I break into Active Directory environments, build the labs I break into, and
write up what happened. This site is where that work lives.

Most of it is self-directed. I work Hack The Box machines while they're still
active — no public writeups to lean on, which is the point — and publish mine
only once the box has retired. Beyond individual machines I've completed the
Dante and P.O.O. Pro Labs, which are multi-host networks rather than single
targets: pivoting between hosts, moving laterally, and chaining an entire
domain rather than popping one box.

Alongside that I've built the infrastructure to attack. A Game of Active
Directory deployment I stood up and troubleshot end to end, and a Splunk
install I pointed at my own domain to see which of my attacks actually
generated an alert. The writeups aim to be followable rather than
impressive — if you can't reproduce it from what I wrote, I haven't finished
writing it.

## Getting here

I came to security sideways. I hold a Bachelor of Music and a Masters of Music
and I currently work in customer support for a financial services company.
Neither is a security job, and I'm not going to pretend otherwise.

What they did give me is the half of consultancy work that isn't technical.
Music therapy is clinical listening and careful documentation with people
who are having a difficult time. Support work is explaining a problem to
someone who didn't ask for it and doesn't share your vocabulary. Penetration
testing is substantially report writing and client debriefs, and I'd rather
arrive already good at that part.

## What I'm looking for

A first role in penetration testing, based in Sydney. I'm most interested in
Active Directory and Windows internals, and I'm equally happy on work that
sits closer to detection — building the lab taught me that the two questions
are the same question from opposite ends.

## What I work with

**Active Directory and Windows** — Kerberos abuse, ACL and delegation
chains, AD CS misconfiguration, credential extraction and reuse.

**Tooling** — BloodHound, Impacket, netexec, Evil-WinRM, hashcat, Metasploit,
nmap, Responder.

**Detection** — Splunk Enterprise, Universal Forwarders, Windows event log
analysis, writing searches against attacks I'd just run.

**Lab infrastructure** — VMware Workstation, Vagrant, GOAD, Windows Server
and domain builds, network segmentation.

**Multi-host networks** — Hack The Box Pro Labs: Dante and P.O.O. Pivoting,
lateral movement, and domain-wide compromise across a network rather than a
single target.

## Certifications

- **eJPT** — eLearnSecurity Junior Penetration Tester
- **[Google Cybersecurity Certificate](https://www.coursera.org/account/accomplishments/specialization/ACNFHDZXRVIJ)** — Coursera specialisation
- **CPTS** — HTB Certified Penetration Testing Specialist, in progress
- **OSCP** — next after CPTS

## Hack The Box

- **Pro Labs** — Dante, P.O.O.
- **Machines** — worked while active; writeups published after retirement

## Get in touch

The best way to reach me is LinkedIn.

- [LinkedIn](https://www.linkedin.com/in/angus-dawson-92b035249/)
- [GitHub](https://github.com/basil9099)
```

- [ ] **Step 2: Create the search page**

`config.yaml` already emits the JSON index and PaperMod already ships `themes/PaperMod/layouts/_default/search.html`. The only missing piece is a content file.

Create `content/search.md`:

```markdown
---
title: "Search"
layout: "search"
url: "/search/"
summary: "Search the writeups"
placeholder: "Search writeups, tools, techniques…"
ShowToc: false
ShowReadingTime: false
ShowBreadCrumbs: false
hideMeta: true
---
```

- [ ] **Step 3: Add both to the menu**

In `config.yaml`, add to `menu.main`:

```yaml
    - name: About
      url: /about/
      weight: 5
    - name: Search
      url: /search/
      weight: 40
```

Weight 5 puts About first, ahead of CTFs at 10. Search goes last at 40.

- [ ] **Step 4: Verify search actually returns results**

```bash
bash scripts/verify-site.sh
hugo server -D
```

Open `http://localhost:1313/search/` and search for `kerberos`. Confirm results appear and link correctly. An empty result set means the JSON index isn't building — check `outputs.home` still includes `JSON` in `config.yaml`.

- [ ] **Step 5: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add content/about.md content/search.md config.yaml
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Add About page and activate search

The site had no page stating who the author is or how to reach him, which
was the largest gap for a visiting employer. Search was configured — the
JSON index was being emitted — but had no page or menu entry, so it was
dead config.
```

---

### Task 8: Social preview card

**Files:**
- Modify: `config.yaml`
- Create: `static/images/og-default.png`

**Interfaces:**
- Consumes: nothing.
- Produces: Open Graph and Twitter card metadata on every page.

> **Do not run `convert` on this machine.** ImageMagick is not installed, but
> `convert` resolves to `C:\WINDOWS\system32\convert.exe` — the Windows
> FAT-to-NTFS filesystem conversion utility. Invoking it on the assumption that
> it is ImageMagick is dangerous. Pillow is not installed either.

- [ ] **Step 1: Create the share image**

Install Pillow and generate the card:

```bash
python -m pip install --quiet Pillow
```

Then run:

```python
from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 630
img = Image.new("RGB", (W, H), "#10141a")
d = ImageDraw.Draw(img)

def font(size):
    for path in ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()

d.rectangle([0, 0, W, 6], fill="#3ddc84")
d.text((80, 240), "Angus Dawson", font=font(76), fill="#e6e9ee")
d.text((80, 350), "Active Directory  ·  Homelab  ·  Detection",
       font=font(34), fill="#3ddc84")
d.text((80, 430), "basil9099.github.io", font=font(26), fill="#8792a3")

img.save("static/images/og-default.png")
print("wrote static/images/og-default.png")
```

Save it as `scripts/make-og-image.py` and run `python scripts/make-og-image.py`. Confirm the file is 1200×630 and that the text is legible when scaled to roughly 300px wide — LinkedIn renders it small.

If Pillow cannot be installed, **stop and tell Angus** rather than proceeding. Do not add `images:` to `config.yaml` pointing at a file that does not exist — a broken OG image reference renders worse than none at all.

- [ ] **Step 2: Add the site description and OG defaults**

Only once the image exists. LinkedIn is the sole contact route, so the card that renders when the URL is pasted there is a first impression. In `config.yaml`, add at the top level:

```yaml
description: "Active Directory attack paths, homelab builds, and detection engineering — CTF writeups and lab notes by Angus Dawson, Sydney."
```

And under `params`:

```yaml
  author: "Angus Dawson"
  keywords: ["penetration testing", "active directory", "hack the box", "homelab", "detection engineering", "cybersecurity"]
  images: ["/images/og-default.png"]
  ShowWordCount: false
```

PaperMod's `head.html` reads `params.images` for the default OG image.

- [ ] **Step 3: Verify the tags render**

```bash
bash scripts/verify-site.sh
grep -o '<meta property="og:[^>]*>' /tmp/*/index.html 2>/dev/null | head
```

Confirm `og:title`, `og:description`, and `og:image` are present. Validate the live card with LinkedIn's Post Inspector only after merging to `main`, since it needs a public URL.

- [ ] **Step 4: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add config.yaml static/images/og-default.png scripts/make-og-image.py
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Add social preview card and site description

LinkedIn is the only contact route on the site, so the preview card that
renders when the URL is shared there is a first impression. It was
previously bare — no description, no OG image.
```

---

### Task 9: Align CI Hugo version and final verification

**Files:**
- Modify: `.github/workflows/deploy.yml:24`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything.
- Produces: the merge-ready branch.

- [ ] **Step 1: Pin CI to the local Hugo version**

`.github/workflows/deploy.yml` pins `0.150.0` while local is `0.165.0`, so previewed output can drift from deployed output. Change:

```yaml
          hugo-version: '0.165.0'
          extended: true
```

Delete the trailing `# or whatever version you're using` comment while you are in there.

- [ ] **Step 2: Update the README**

The README describes the site as a blog. Add the About page and search to its structure list, and add a line under "Running Locally" noting the verification script:

```markdown
# Check the build and the copy rules
bash scripts/verify-site.sh
```

- [ ] **Step 3: Run the full verification**

```bash
bash scripts/verify-site.sh
```

Expected: every assertion passes, `failed: 0`, exit 0. If any assertion still fails, fix it before proceeding — do not merge a partially green branch.

- [ ] **Step 4: Manual checks the script cannot make**

Run `hugo server -D` and confirm each of these by eye:

- Homepage in light mode and dark mode: no unreadable text, no invisible borders.
- Resize to 375px, 768px, and 1440px. The capability strip and featured grid must reflow without horizontal scroll.
- Every post shows a difficulty pill with colour, including the GOAD post.
- No `##` prefixes visible before any heading.
- Code blocks have no fake title bar and no `sh` label.
- `/search/` returns results for `kerberos`.
- `/about/` renders, and its LinkedIn link opens the correct profile.
- Tab through the homepage: focus outlines must be visible in both themes.

- [ ] **Step 5: Stage the work and hand back — do not commit**

Angus owns every commit and push in this repository. Stage the files, show the diff, and stop:

```bash
git add .github/workflows/deploy.yml README.md
git --no-pager diff --staged --stat
```

Do not run `git commit`. Do not run `git push`. Report what changed and wait.

Suggested commit message, for Angus to use or ignore:

```text
Align CI Hugo version with local and document verification

CI pinned 0.150.0 while local development runs 0.165.0, so previewed
output could drift from what deployed.
```

- [ ] **Step 6: Hand back for review before merging**

Do not merge to `main` and do not push. `main` auto-deploys on push, so the merge is Angus's call once he has previewed the branch locally and read the About page copy in his own voice.

Report: what changed, anything that deviated from this plan, and the final `verify-site.sh` output.

---

## Notes for the executor

**Running Hugo.** It may not be on `PATH` in an existing shell. Either open a fresh terminal or use the full path:

```bash
export PATH="$PATH:/c/Users/angus/AppData/Local/Microsoft/WinGet/Packages/Hugo.Hugo.Extended_Microsoft.Winget.Source_8wekyb3d8bbwe"
```

**The About page copy is a draft, not a fact source.** Every factual claim in it came from Angus and is recorded in the spec's "Biographical facts" table. If you find yourself wanting to add a detail that is not in that table, don't — ask.

**Never commit or push anything.** Angus owns all commits and pushes. Stage with `git add`, report the diff, stop. `main` deploys on push, so an accidental push is a live deployment.

**Facts you may state, from the spec.** A Bachelor of Music, then a Masters of Music Therapy. The Bachelor is NOT a music therapy degree. Google Cybersecurity Certificate, credential at `https://www.coursera.org/account/accomplishments/specialization/ACNFHDZXRVIJ`. HTB Pro Labs Dante and P.O.O. completed. Machines solved while active, published after retirement. Anything not in the spec's "Biographical facts" table is not yours to assert.
