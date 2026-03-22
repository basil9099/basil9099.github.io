---
title: "Gobuster & Feroxbuster — Cheat Sheet"
date: 2026-03-22
author: "Basil9099"
tags: ["cheatsheet", "gobuster", "feroxbuster", "web", "fuzzing", "ctf", "htb"]
categories: ["Cheats"]
summary: "Quick reference for directory/file bruteforcing and vhost enumeration with gobuster and feroxbuster."
---

## Quick Start

```bash
# Gobuster — fast directory brute-force
gobuster dir -u http://<IP> -w /usr/share/seclists/Discovery/Web-Content/common.txt

# Feroxbuster — recursive directory brute-force
feroxbuster -u http://<IP> -w /usr/share/seclists/Discovery/Web-Content/common.txt
```

---

## Gobuster

### Directory / File Fuzzing (`dir` mode)

```bash
gobuster dir \
  -u http://<IP> \
  -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt \
  -x php,html,txt,bak \
  -t 50 \
  -o gobuster_dir.txt

# With authentication
gobuster dir -u http://<IP> -w <wordlist> -U admin -P password

# Custom headers (e.g. cookies)
gobuster dir -u http://<IP> -w <wordlist> -H "Cookie: session=abc123"

# Follow redirects
gobuster dir -u http://<IP> -w <wordlist> -r

# Filter by status code
gobuster dir -u http://<IP> -w <wordlist> --exclude-length 0
```

**Key flags:**

| Flag | Description |
|------|-------------|
| `-u` | Target URL |
| `-w` | Wordlist path |
| `-x` | Extensions to append (e.g. `php,html,txt`) |
| `-t` | Threads (default 10, try 50) |
| `-o` | Output file |
| `-r` | Follow redirects |
| `-k` | Skip TLS certificate verification |
| `-H` | Add custom header |
| `-b` | Blacklist status codes (e.g. `404,403`) |
| `-s` | Whitelist status codes (e.g. `200,301`) |
| `--timeout` | HTTP timeout |

---

### DNS Subdomain Enumeration (`dns` mode)

```bash
gobuster dns \
  -d <domain.com> \
  -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  -t 50 \
  -o gobuster_dns.txt

# Show IP addresses in output
gobuster dns -d <domain.com> -w <wordlist> -i
```

---

### VHost Enumeration (`vhost` mode)

```bash
gobuster vhost \
  -u http://<IP> \
  -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  --append-domain \
  -t 50 \
  -o gobuster_vhost.txt
```

> Tip: Add discovered vhosts to `/etc/hosts` — `<IP>  <vhost.domain.com>`

---

## Feroxbuster

Feroxbuster is recursive by default and handles edge cases well.

### Directory / File Fuzzing

```bash
feroxbuster \
  -u http://<IP> \
  -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt \
  -x php,html,txt \
  --depth 3 \
  -t 50 \
  -o ferox_out.txt

# With cookies/headers
feroxbuster -u http://<IP> -w <wordlist> -H "Cookie: session=abc123"

# HTTPS (skip cert check)
feroxbuster -u https://<IP> -w <wordlist> -k

# Filter out specific response sizes (removes false positives)
feroxbuster -u http://<IP> -w <wordlist> --filter-size 4242

# Filter by word count in response
feroxbuster -u http://<IP> -w <wordlist> --filter-words 10
```

**Key flags:**

| Flag | Description |
|------|-------------|
| `-u` | Target URL |
| `-w` | Wordlist path |
| `-x` | Extensions |
| `--depth` | Max recursion depth (default unlimited) |
| `-t` | Threads (default 50) |
| `-o` | Output file |
| `-k` | Insecure TLS |
| `-H` | Custom header |
| `--filter-status` | Filter out status codes (e.g. `404,403`) |
| `--filter-size` | Filter by response size (bytes) |
| `--filter-words` | Filter by word count |
| `--no-recursion` | Disable recursive scanning |
| `--resume-from` | Resume from a saved state file |

---

## Wordlists (SecLists)

| Wordlist | Use Case |
|----------|----------|
| `Discovery/Web-Content/common.txt` | Quick, small (4k entries) |
| `Discovery/Web-Content/directory-list-2.3-medium.txt` | Standard dir brute (220k) |
| `Discovery/Web-Content/directory-list-2.3-big.txt` | Thorough dir brute (1.2M) |
| `Discovery/Web-Content/raft-medium-directories.txt` | Good alternative to dirbuster |
| `Discovery/Web-Content/raft-medium-files.txt` | File focused |
| `Discovery/Web-Content/CMS/<cms>/` | CMS-specific (WordPress, Drupal…) |
| `Discovery/DNS/subdomains-top1million-5000.txt` | DNS/vhost (fast) |
| `Discovery/DNS/subdomains-top1million-20000.txt` | DNS/vhost (thorough) |

> SecLists install: `sudo apt install seclists` or clone from https://github.com/danielmiessler/SecLists

---

## Extension Cheatsheet

Pick extensions based on what the server is running:

| Tech Stack | Extensions |
|------------|------------|
| PHP | `php,php5,php7,phtml` |
| ASP.NET | `asp,aspx,ashx,asmx` |
| Java | `jsp,jspx,do,action` |
| Generic | `html,htm,txt,bak,old,zip,conf,config,log` |
