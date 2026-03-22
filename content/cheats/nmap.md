---
title: "Nmap — Cheat Sheet"
date: 2026-03-22
author: "Basil9099"
tags: ["cheatsheet", "nmap", "recon", "ctf", "htb"]
categories: ["Cheats"]
summary: "Quick reference for nmap flags and workflows used in HTB/CTF machines."
---

## HTB Workflow

A reliable three-phase scan pattern for HTB machines:

```bash
# 1. Quick scan — find open ports fast
nmap -p- --min-rate 5000 -T4 <IP> -oN ports.txt

# 2. Targeted service scan on discovered ports
nmap -p <PORTS> -sC -sV <IP> -oN services.txt

# 3. Deep script scan if interesting services found
nmap -p <PORTS> --script vuln <IP> -oN vulns.txt
```

---

## Common Flags

| Flag | Description |
|------|-------------|
| `-sS` | SYN (stealth) scan — default for root |
| `-sV` | Service/version detection |
| `-sC` | Default NSE scripts (equiv. `--script=default`) |
| `-A` | Aggressive: `-sV -sC -O --traceroute` |
| `-p-` | Scan all 65535 ports |
| `-p <ports>` | Specific ports, e.g. `-p 22,80,443` or `-p 1-1024` |
| `-Pn` | Skip host discovery (treat host as up) |
| `-n` | Disable DNS resolution (faster) |
| `-T4` | Faster timing (T0–T5, T4 is good for HTB) |
| `--min-rate 5000` | Send packets no slower than 5000/sec |
| `-O` | OS detection |
| `-oN <file>` | Normal output to file |
| `-oX <file>` | XML output |
| `-oG <file>` | Grepable output |
| `-oA <basename>` | All three formats at once |
| `-v` / `-vv` | Verbose output |

---

## Host Discovery

```bash
# Ping sweep — find live hosts on a subnet
nmap -sn 10.10.10.0/24

# Skip ping, assume host is up (useful for HTB)
nmap -Pn <IP>

# ARP scan (faster, requires root, same subnet only)
nmap -PR -sn 10.10.10.0/24
```

---

## UDP Scanning

UDP is slow — scan only top ports unless you have a reason:

```bash
# Top 20 UDP ports
nmap -sU --top-ports 20 <IP>

# Common UDP services
nmap -sU -p 53,67,68,69,123,161,162,500 <IP>
```

---

## NSE Scripts

```bash
# List available scripts for a category
ls /usr/share/nmap/scripts/ | grep smb

# Run a specific script
nmap --script smb-vuln-ms17-010 <IP>

# Run a category of scripts
nmap --script vuln <IP>
nmap --script discovery <IP>
nmap --script "smb-*" <IP>

# Pass script arguments
nmap --script http-brute --script-args userdb=users.txt,passdb=pass.txt <IP>
```

**Useful script categories:**

| Category | Use Case |
|----------|----------|
| `default` | Safe, informational (same as `-sC`) |
| `vuln` | Check for known vulnerabilities |
| `auth` | Authentication bypass checks |
| `brute` | Brute-force login scripts |
| `discovery` | Enumerate hosts/services |
| `exploit` | Actively exploit (use carefully) |

---

## Common One-Liners

```bash
# All ports + service scan in one pass
nmap -p- -sV -sC --min-rate 5000 -T4 <IP> -oA full

# Quick web recon
nmap -p 80,443,8080,8443 -sV -sC <IP>

# SMB enumeration
nmap -p 139,445 --script smb-enum-shares,smb-enum-users,smb-os-discovery <IP>

# FTP check anonymous login
nmap -p 21 --script ftp-anon <IP>

# NFS shares
nmap -p 111,2049 --script nfs-ls,nfs-showmount <IP>
```
