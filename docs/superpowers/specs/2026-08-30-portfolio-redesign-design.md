# Portfolio Redesign — Design

**Date:** 2026-08-30
**Repo:** basil9099.github.io (Hugo + PaperMod, deployed to GitHub Pages)
**Author:** Angus Dawson

## Problem

The site publishes strong technical work — Active Directory attack chains, an ADCS/ESC15 exploitation writeup, a self-built GOAD lab, Splunk detection experiments — but it is not currently structured to convert a visitor into a job callback.

Three concrete failures:

1. **No identity or contact route.** There is no About page. Nothing on the site states who the author is, where he is, what he is looking for, or how to reach him. There is no link to LinkedIn, GitHub, or a CV.
2. **The homepage opens on jargon.** The first screen is a simulated terminal describing the author as a "security learner" and "homelab tinkerer", followed immediately by post summaries written as raw attack chains (`Henry -> targeted Kerberoast on Alfred -> AddSelf to INFRASTRUCTURE ...`). A non-specialist screener has no way in.
3. **Unfinished-looking details.** Search is configured but non-functional, post metadata is inconsistent across four competing schemes, and one post renders a wall of untruncated text where every other post shows a summary.

## Goals

- A visitor with no security background can identify, within roughly 30 seconds: who Angus is, what he does, what he is looking for, and how to contact him.
- A technical reader reaching the same page finds depth and credible tradecraft, and the site's character is preserved for them.
- The site reads as finished and deliberate rather than as a work in progress.

## Non-goals

- Migrating off Hugo or PaperMod.
- Restructuring URLs or moving the blog to a subpath. Existing permalinks stay valid.
- Adding analytics, comments, or a newsletter.
- Rewriting the technical body content of any writeup.

## Audience model

The site serves two audiences **in sequence**, and the design is organised around that sequence rather than trying to average them:

| Stage | Reader | Needs | Served by |
|---|---|---|---|
| First 30s | Recruiter / HR screener, often non-technical | Name, role fit, credentials, contact | Hero, capability strip, About page |
| Deep read | Security engineer or hiring manager | Methodology, rigour, range | Featured work, writeups, terminal styling |

Positioning leads offensive (junior penetration tester / red team) because that is where the evidence is strongest, while staying broad enough not to disqualify Angus from adjacent security roles.

## Approach

**Layered landing.** One homepage that sequences from professional to technical. The terminal aesthetic is retained but demoted from page-wide wallpaper to a scoped accent — it appears in writeup listings, post bodies, code blocks, and the writeup info card, but no longer dominates the first screen.

Two approaches were considered and rejected:

- **Two front doors** (portfolio landing at `/`, blog moved to `/writeups/`). Cleanest audience separation, but with 12 posts the landing page would be mostly navigation, and it forces redirect work for a benefit the layered landing already delivers.
- **Restrained restyle** (calm the effects, change nothing structural). Least work, but leaves the screener problem unsolved since the homepage would still open on an attack-chain wall.

## Information architecture

Homepage section order:

1. **Hero** — real name, then a capability-led positioning line rather than a job title: "Active Directory attack paths, lab building, and detection — working toward a first role in penetration testing." Angus does not yet hold a penetration testing role, so the headline states what he can demonstrably do and where he is heading, claiming no title he does not hold. Below it: certification status, location, and buttons to About, LinkedIn, and GitHub.
2. **Capability strip** — three plain-English areas of work (AD attack paths, lab building, detection engineering), each one line, no jargon. This is the screener's ten seconds.
3. **Featured work** — three curated posts, selected via a `featured: true` frontmatter flag rather than by recency:
   - TombWatcher (deepest chain: Kerberoast to gMSA to ADCS/ESC15)
   - GOAD-Light lab build (demonstrates building infrastructure, not only solving puzzles)
   - Splunk install and bruteforce detection (demonstrates range beyond offense)
4. **Recent writeups** — the existing per-section listings, retaining the `~/ctf $ ls -lt` terminal section headers.

Navigation gains **About** and **Search**. Existing CTFs / Homelab / Cheats entries are unchanged.

## Visual system

### Palette

Neutral slate ground rather than the current green-tinted near-black, so green functions as a signal colour rather than as a cast over the whole page. Both light and dark themes are supported and the PaperMod theme toggle is re-enabled (`disableThemeToggle` currently suppresses it).

| Token | Dark | Light |
|---|---|---|
| `--theme` (page) | `#10141a` | `#ffffff` |
| `--entry` (card) | `#161b23` | `#f7f8fa` |
| `--code-block-bg` | `#0c1016` | `#f2f4f7` |
| `--border` | `#232a35` | `#e2e5ea` |
| `--border-strong` | `#303947` | `#cdd3db` |
| `--primary` (headings) | `#e6e9ee` | `#14181f` |
| `--content` (body) | `#c3cad5` | `#333b47` |
| `--secondary` (meta) | `#8792a3` | `#5a6472` |
| `--accent` | `#3ddc84` | `#12694a` |
| `--accent-dim` | `#2fae68` | `#0f5a3f` |

Accent-on-background contrast meets WCAG AA in both themes (`#12694a` on white is approximately 5.6:1; `#3ddc84` on `#10141a` is far above threshold).

Difficulty pills need light-theme colour variants, as they are currently defined only for dark. They also need a fifth variant: the CSS defines `easy` / `medium` / `hard` / `insane`, but `goad-light-setup.md` sets `difficulty: "Intermediate"`, which matches no rule and renders unstyled. Homelab posts will use a separate `easy` / `intermediate` / `advanced` vocabulary, distinct from the Hack The Box difficulty scale used by CTF posts.

### Typography

- **Body and UI:** Inter, 16–17px, line-height 1.7, content column capped at roughly 68 characters. Replaces the current use of JetBrains Mono for all body copy, which is tiring to read and reads as a hobby project.
- **Monospace:** JetBrains Mono, retained strictly for code blocks, inline code, metadata, difficulty pills, the hero, and terminal section headers.

### Effects removed

| Removed | Reason |
|---|---|
| Scanline overlay (`body::before`) | Decorative only; slightly degrades text rendering. |
| Neon glow shadows on hover and nav | The strongest "gamer aesthetic" signal on the site. |
| `● ● ●` / `sh` title bar on every code block | Also inaccurate — it labels PowerShell, output dumps, and config files all as `sh`. Retained for the hero terminal only. |
| `##` / `###` injected before every heading | Reads as markdown that failed to render, and is announced by screen readers. |

Retained: the blinking hero cursor, difficulty pills, the terminal-framed writeup info card, and the `~/section $ ls -lt` listing headers.

## Content changes

### New pages

- **`content/about.md`** — positioning statement, the career-change story, what Angus is looking for, skills grouped by area (AD/Windows, tooling, detection, lab infrastructure), certification status, and a contact block pointing to LinkedIn. Prose to be drafted from existing writeups, then reviewed and edited by Angus. Section order and content are specified under "Biographical facts" below.
- **`content/search.md`** — a stub page with `layout: search`. `config.yaml` already emits the JSON index PaperMod's search requires, but with no page and no menu entry the feature is currently dead configuration.

### Metadata normalisation

- `author` becomes `Angus Dawson` on every post. It is currently `Basil9099` on four posts, `Angus Dawson` on one, and absent on another.
- `difficulty`, `platform`, and `os` added to all CTF posts so the writeup info card renders everywhere, rather than only on `blue-htb.md`.
- Categories unified to exactly three values matching the site's sections: `CTF Writeups`, `Homelab`, and `Cheat Sheets`. Five values are currently in use across four competing schemes (`CTF Writeups`, `HTB`, `writeup`, `pentest`, `Homelab`). Platform and technology detail moves to `tags`, where it already lives.
- `summary` added to `optimum-htb.md`, which currently auto-truncates into a wall of raw text on the homepage while every other card shows a clean one-liner.
- `featured: true` added to the three curated posts.

### Summaries

Existing attack-chain summaries are **kept intact** and a single plain-English lead sentence is added before each. Nothing is deleted; the chain remains for technical readers, and the lead sentence gives a screener a way in.

### Social preview

The site has no description and no Open Graph image configuration, so pasting the URL into LinkedIn renders a bare card. Since LinkedIn is the only contact route, this card is a first impression and will be configured: site description, OG title/description/image defaults, and a default share image.

## Technical notes

- **Files touched:** `config.yaml`, `assets/css/extended/terminal.css` (substantial rewrite into light/dark token sets), `layouts/index.html`, `layouts/partials/extend_head.html`, `layouts/partials/boxinfo.html`, `layouts/_default/single.html`, all files under `content/`, plus a new default social image under `static/`.
- **Hugo version drift:** `.github/workflows/deploy.yml` pins Hugo `0.150.0` while the local install is `0.165.0` extended. These should be aligned to `0.165.0` so local previews match deployed output.
- **`.gitignore`:** add `.superpowers/` (brainstorming session artifacts).
- **Fragility to watch:** `layouts/partials/boxinfo.html` calls `index .Params.series 0` unguarded. It is tolerated by the current build but should be guarded with `with` while that partial is being edited.

## Biographical facts

Supplied by Angus and authoritative for all copy on the site:

| Field | Value |
|---|---|
| Name | Angus Dawson |
| Location | Sydney, NSW, Australia |
| Current role | Customer support, financial services sector (employer not named — see omissions) |
| Background | Career changer — Bachelor of Music, then Masters of Music Therapy |
| Target | Penetration testing |
| Certifications | eJPT (held); Google Cybersecurity Certificate (held); CPTS (working toward); OSCP (stated goal) |
| Google cert credential | https://www.coursera.org/account/accomplishments/specialization/ACNFHDZXRVIJ |
| Practical experience | Hack The Box — machines solved while **active**, published only after retirement; Pro Labs: Dante and P.O.O.; self-built AD and detection labs |
| Contact | LinkedIn only — https://www.linkedin.com/in/angus-dawson-92b035249/ |
| GitHub | https://github.com/basil9099 |
| CV | Hosted on LinkedIn only. No PDF on this site. |

### Evidence worth foregrounding

Two facts materially strengthen the case and must not be buried in a list:

- **Machines are solved while active, not retired.** An active Hack The Box
  machine has no public writeups, so solving one is unaided problem-solving
  rather than following someone else's path. Publishing only after retirement
  is also the platform's rule, so the same fact evidences discipline.
- **Pro Labs: Dante and P.O.O.** These are multi-host networks requiring
  pivoting, lateral movement, and domain-wide attack chains — substantially
  closer to a real engagement than a single box, and uncommon for a candidate
  with no professional experience.

### How the career change is framed

The music therapy Masters and the customer support role are stated plainly as
assets, in one or two sentences, and not apologised for. The angle: a completed
Masters evidences sustained academic rigour, and clinical listening plus
customer-facing work map directly onto the reporting and client-debrief half of
consultancy penetration testing — a skill set firms find harder to hire than raw
technical ability.

### Deliberate omissions

These are excluded from all published copy:

- **Any implication of professional penetration testing experience.** Angus has
  none yet. Lab and CTF experience is labelled honestly as self-directed.
  Overclaiming is a liability in a first technical interview.
- **The financial reason OSCP is deferred.** OSCP appears as a stated goal. Cost
  is private and reads as a constraint rather than a plan.
- **Personal email address.** LinkedIn is the sole contact route, by Angus's
  explicit choice.
- **The current employer's name.** Referred to only as "financial services" or
  "a financial services company". Angus is job-hunting while employed, and
  naming the employer on a public page invites avoidable awkwardness.

### About page section order

1. Positioning statement — what he does, two sentences.
2. The career change — music therapy to security, framed as above.
3. What he is looking for — a first penetration testing role, Sydney-based.
4. Skills, grouped: AD and Windows, tooling, detection, lab infrastructure.
5. Certifications and current study.
6. Contact — LinkedIn, with GitHub alongside.

## Verification

- `hugo --minify` completes without errors or warnings.
- Every CTF and homelab post renders a writeup info card with a correctly styled difficulty pill. Cheat sheets are exempt — difficulty does not apply to them.
- No post card on the homepage shows untruncated body text.
- Search returns results for a known term.
- Theme toggle switches cleanly; no element is unreadable in either theme.
- Text contrast meets WCAG AA in both themes.
- Layout holds at 375px, 768px, and 1440px widths.
- No `##` prefixes or scanlines remain in rendered output.
- The About page states name, target role, location, and a working LinkedIn link.
- No published copy claims professional penetration testing experience, states a job title Angus does not hold, mentions certification costs, or exposes a personal email address.

## Deployment

`main` auto-deploys on push via GitHub Actions. Work proceeds on a `redesign` branch and is merged only on Angus's approval, so nothing reaches the live site prematurely.
