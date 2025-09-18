---
title: "Windows Server with Active Directory (AD) — Homelab"
date: 2025-09-18
author: "Basil9099"
tags: ["homelab","active-directory","windows","ad","lab"]
categories: ["Homelab"]
summary: "Overview of my Active Directory homelab: domain setup, users, security exercises, and next steps for monitoring and detection."
---

> 🖥️ **Homelab note**
> This post documents the Windows Server with Active Directory environment I use for training, testing, and detection exercises.

---

## Overview

I run a fully configured **Windows Server** acting as an **Active Directory (AD)** domain controller in my cybersecurity homelab. The environment simulates a realistic enterprise domain and is used for practicing penetration testing techniques, AD security administration, and detection exercises.

---

## Why run Active Directory in the lab?

- **Real-world scenarios** — replicate corporate AD environments for hands-on learning.  
- **User & group management** — practice account lifecycle, permissions, and role separation.  
- **Penetration testing** — safely test AD-specific techniques (Kerberoasting, AS-REP, delegation, etc.).  
- **Detection & logging** — instrument the lab to understand log sources, event IDs, and alert tuning.

---

## Simulated user accounts

Use these sample accounts for exercises and role-based scenarios.

| Username | First name | Last name | Role / Description     | Office  | Phone         | Email                          |
|----------|------------|-----------|------------------------|---------|---------------|-------------------------------|
| alice.it | Alice      | Smith     | Helpdesk Analyst       | HQ-102  | +1 (555) 0102 | alice.it@homelab.local        |
| bob.hr   | Bob        | Johnson   | HR Assistant           | HQ-201  | +1 (555) 0103 | bob.hr@homelab.local          |
| carol.finance | Carol | Bright    | Financial Analyst      | HQ-301  | +1 (555) 0104 | carol.finance@homelab.local   |
| david.bright | David  | Bright    | Finance Manager        | HQ-302  | +1 (555) 0105 | david.bright@homelab.local    |

*Screenshot: ADUC with lab users provisioned (Helpdesk, HR, Finance, IT).*

> Tip: store these users in a dedicated organizational unit (OU) and apply realistic group memberships (e.g., `Domain Users`, `Finance`, `Helpdesk`) to practice ACL and delegation scenarios.

<p align="center">
  <img src="/images/homelab/windows-ad/Windows-10_AD_Setup.png" 
       alt="Active Directory Users and Computers showing LabUsers OU" 
       style="max-width:100%;height:auto;" />
  <br><em>Active Directory Users and Computers (ADUC) with LabUsers OU provisioned.</em>
</p>



---

## Features & configuration highlights

- **Domain**: `homelab.local` (internal DNS + AD-integrated DNS)  
- **Group Policy**: enforced password complexity, lockout policy, and baseline login restrictions.  
- **Role-based access**: roles and groups created to mirror real org structures (Helpdesk, HR, Finance).  
- **Service accounts**: segregated service accounts for apps and scheduled tasks; test constrained delegation scenarios in a controlled way.  
- **Backups & snapshots**: use VM snapshots and exported backups before major changes or offensive testing.

---

## Usage tips & security exercises

Here are practical exercises you can run in this lab:

---

### Privilege escalation
- Audit local and domain group memberships (`whoami /groups`, AD ACLs).  
- Search for misconfigured service accounts, weak service principal names (SPNs), and vulnerable scheduled tasks.

---

### Authentication attacks
- Simulate **password spraying** and **brute-force** at safe rates against test accounts (do not test on production).  
- Practice **Kerberoasting** and **AS-REP roasting** on appropriate accounts.

---

### Log analysis & detection
- Collect Windows Event Logs (Security, System, Application) to a central log host.  
- Simulate suspicious behavior (e.g., lateral movement) and tune alerts for Event IDs relevant to AD compromise.

---

## Quick commands & references

**AD enumeration (from attacker host with ldapsearch / impacket):**
```bash
# LDAP query example (replace with your DC)
ldapsearch -x -H ldap://dc.homelab.local -b "DC=homelab,DC=local" "(objectClass=user)" sAMAccountName
```
Kerberos quick tests (Linux attacker):
```bash
kinit alice.it@HOMELAB.LOCAL
klist
```

**Windows checks (on domain controller / domain-joined host):**

# list policies and domain info
```bash
Get-ADDomain
Get-ADUser -Filter * -Properties MemberOf | Select sAMAccountName, MemberOf
```
# Next steps / roadmap

Planned improvements to the lab:

- Integrate EDR (Endpoint Detection & Response) for behavioral testing.

- Configure SIEM (e.g., Splunk/ELK) and dashboards for AD-centric alerts.

- Add simulated phishing and phishing-resiliency exercises.

- Deploy additional network services (Exchange, file servers) for richer attack surfaces.

# Notes & safe-use reminders

This environment is for authorized testing only. Don’t run these exercises against production networks or systems you don’t own.

Take snapshots or backups before performing offensive tests to ensure you can restore the lab quickly.

# Resources

- Microsoft Docs: Active Directory overview

- Impacket & Rubeus for AD testing and Kerberos tooling

- MITRE ATT&CK for enterprise techniques and detection guidance
