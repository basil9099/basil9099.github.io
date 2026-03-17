# Angus Dawson — Homelab & CTF Blog

A personal cybersecurity blog built with [Hugo](https://gohugo.io/) and the [PaperMod](https://github.com/adityatelange/hugo-PaperMod) theme.

The blog covers:

- **CTF Writeups** — Step-by-step walkthroughs of retired Hack The Box and TryHackMe machines, with emphasis on methodology and key takeaways.
- **Homelab Documentation** — Notes from Active Directory labs, Kerberos troubleshooting, detection experiments, and other hands-on projects.
- **Cheat Sheets** — Practical reference material for use when testing or studying.

---

## Live Site

[https://basil9099.github.io](https://basil9099.github.io)

---

## Repository Structure

```
content/           # Blog posts (Markdown)
├── ctf/           # CTF writeups
├── homelab/       # Homelab notes
└── cheats/        # Quick references
static/images/     # Screenshots and diagrams
themes/            # PaperMod theme (git submodule)
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
```

---

## Deployment

Every push to `main` triggers a GitHub Actions workflow that builds the Hugo site and publishes it to GitHub Pages automatically.
