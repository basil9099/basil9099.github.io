# Angus Dawson — Homelab & CTF Blog

A personal cybersecurity blog and portfolio built with [Hugo](https://gohugo.io/) and the [PaperMod](https://github.com/adityatelange/hugo-PaperMod) theme.

The blog covers:

- **CTF Writeups** — Step-by-step walkthroughs of retired Hack The Box machines, with emphasis on methodology and key takeaways.
- **Homelab Documentation** — Notes from Active Directory labs, Kerberos troubleshooting, detection experiments, and other hands-on projects.
- **Cheat Sheets** — Practical reference material for use when testing or studying.

It also includes an About page and site search.

---

## Live Site

[https://basil9099.github.io](https://basil9099.github.io)

---

## Repository Structure

```
content/           # Blog posts and pages (Markdown)
├── ctf/           # CTF writeups
├── homelab/       # Homelab notes
├── cheats/        # Quick references
├── about.md       # About page
└── search.md      # Search page
static/images/     # Screenshots and diagrams
themes/            # PaperMod theme (git submodule)
scripts/           # Build/verification scripts (verify-site.sh)
.github/           # GitHub Actions workflow for Pages
```

---

## Running Locally

```bash
# Clone the repo with submodules
git clone --recurse-submodules https://github.com/basil9099/basil9099.github.io.git
cd basil9099.github.io

# Start the development server
hugo server -D

# Open http://localhost:1313

# Check the build and the copy rules
bash scripts/verify-site.sh
```

---

## Deployment

Every push to `main` triggers a GitHub Actions workflow that builds the Hugo site and publishes it to GitHub Pages automatically.
