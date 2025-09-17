# Angus Dawson — Homelab & CTF Blog

This repository contains my personal cybersecurity blog, built with [Hugo](https://gohugo.io/) and the [PaperMod](https://github.com/adityatelange/hugo-PaperMod) theme.

The blog focuses on:

- 🧩 **CTF Writeups** — step-by-step walkthroughs of retired Hack The Box and TryHackMe machines, with emphasis on methodology and takeaways.
- 🖥️ **Homelab Documentation** — notes from my Active Directory labs, Kerberos troubleshooting, detection experiments, and other hands-on projects.
- 📒 **Cheat Sheets** — practical reference material I use when testing or studying.

---

## 🔗 Live Blog

👉 [https://basil9099.github.io](https://basil9099.github.io)

---

## 📂 Repo Structure

content/ # Blog posts (Markdown)
├─ ctf/ # CTF writeups
├─ homelab/ # Homelab notes
└─ cheats/ # Quick references
static/images/ # Screenshots and diagrams
themes/ # PaperMod theme (git submodule)
.github/ # GitHub Actions workflow for Pages

yaml
Copy code

---

## ⚙️ Running Locally

```bash

# clone repo (with submodules)

git clone --recurse-submodules https://github.com/basil9099/basil9099.github.io.git
cd basil9099.github.io

# run locally

hugo server -D

# open http://localhost:1313

🛠️ Deployment

Every push to main triggers a GitHub Actions workflow that builds the Hugo site and publishes it to GitHub Pages.
