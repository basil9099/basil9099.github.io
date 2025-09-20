---
title: "Phishing simulation — GoPhish lab guide"
date: "2025-09-20"
tags: ["phishing","gophish","social-engineering","lab"]
draft: false
summary: "Step-by-step lab guide to run a safe phishing simulation using GoPhish and SET (Social-Engineer Toolkit). For isolated lab environments only."
---

> **Spoiler / ethics:** for lab use only. Do **not** deploy this against real users or networks you don't own or have explicit permission to test. Phishing is illegal and harmful outside of authorized environments.

## TL;DR

1. Create a sending profile (SMTP + credentials).
2. Build a landing page (paste SET `index.html`), add redirect to the real site.
3. Build the email template (paste 2-step verification HTML), enable “change links to landing page”.
4. Create and launch a campaign (use attacker IP + listener port in URL).
5. Monitor the campaign — captured creds and metadata appear in GoPhish.

---

## Tools used

- **GoPhish** — phishing framework
- **Social-Engineer Toolkit (SET)** — landing-page and email templates
- A lab attacker VM (Kali) and isolated target VM/host

---

## Full step-by-step

---

### 1. Start GoPhish
Open the GoPhish dashboard in your attacker VM (e.g. `http://localhost:3333` or `http://<ATTACKER_IP>:3333` depending on your setup).

![GoPhish dashboard](/images/homelab/phishing_simulation/dashboard.png)

---

### 2. Set up a Sending Profile
1. Go to **Sending Profiles → New Profile**.
2. SMTP server (example): `smtp.gmail.com:587`.
3. Use a lab Gmail account and an **app password** or other valid SMTP credentials.
4. Save and **Send a test email** to verify SMTP connectivity.

![Sending profile](/images/homelab/phishing_simulation/sending_profile.png)

> Tip: use a throwaway lab account and app passwords — keep credentials isolated to the lab.

---

### 3. Create a Landing Page
1. In GoPhish: **Landing Pages → New Landing Page**.
2. Give it a name (e.g. `Google 2FA clone`).
3. Paste the HTML template from SET into the landing page body.

![Landing Page](/images/homelab/phishing_simulation/landing_page.png)

Typical SET path on Kali:

```
/usr/share/set/src/html/templates/google/index.html
```
![SET - Social Engineering Toolkit template](/images/homelab/phishing_simulation/set_template.png)

![Copy template](/images/homelab/phishing_simulation/copy_html.png)

![Paste template](/images/homelab/phishing_simulation/paste_html.png)

4. Add a redirect to the real site after the form submits to keep the illusion intact. For example:

```html
<script>
  // after capturing creds, redirect to the real Google site
  window.location = "https://account.google.com";
</script>
```

5. Save the landing page.


---

### 4. Create the Email Template
1. In GoPhish: **Email Templates → New Template**.
2. Copy the *2-step verification* (or similar) HTML source from SET and paste it into the email body.
3. Tick **“Change links to landing page”** so GoPhish rewrites links to point at your hosted phishing page.
4. Add a realistic subject line, e.g. `Action required: Confirm your 2-Step Verification`.
5. Save the template.

![Email template](/images/homelab/phishing_simulation/email_template.png)

---

### 5. Create and Launch a Campaign
1. **Campaigns → New Campaign**.
2. Choose the Email Template and Landing Page you created.
3. Add recipient addresses (lab addresses only).
4. **Important:** For the campaign URL field, use your attacker machine's IP and include the listener port if required. Example:

![Paste template](/images/homelab/phishing_simulation/paste_html.png)

```
http://<ATTACKER_IP>:8080#
# e.g. http://192.168.56.101:8080#
```

![New GoPhish campaign](/images/homelab/phishing_simulation/new_campaign.png)

- If you see errors, confirm the port is included. GoPhish commonly serves landing pages on ports such as **8080** or **3333**.
- Launch the campaign.

---

### 6. Test & Validate
1. Refresh the GoPhish campaign page — it should show the email as **Sent**.
![Test Email](/images/homelab/phishing_simulation/test_email.png)


2. From the target VM or another host, open the received email and click the phishing link.
![Phishing email](/images/homelab/phishing_simulation/phishing_email.png)


3. Submit credentials on the landing page.
![User inserts credentials](/images/homelab/phishing_simulation/insert_credentials.png)

4. Confirm the browser address bar shows your attacker IP (this confirms redirection to your hosted page).

5. In GoPhish, open the campaign details and expand the drop-down — captured credentials and metadata (IP, user-agent, time) will be visible.
![GoPhish results](/images/homelab/phishing_simulation/results.png)

![User's captured credentials on GoPhish](/images/homelab/phishing_simulation/captured_credentials.png)

---

## Troubleshooting
- **SMTP test fails**
  - Double-check username/password or app password.
  - Ensure outbound firewall rules allow SMTP egress from the attacker VM.

- **Landing page not serving / 404**
  - Confirm the GoPhish listener port and include it in URLs (e.g., `:8080`).

- **Clicked link redirects to wrong page**
  - Verify that **Change links to landing page** was checked when importing the email.

- **No credentials captured**
  - Confirm the landing page form `action` posts to a handler GoPhish captures. The SET template typically includes compatible form handling.
  - Check GoPhish logs for server-side errors.

---

## Safety & operational notes
- Always use **isolated lab networks** (host-only or internal virtual networks) and throwaway accounts.
- Rotate and document lab credentials — never reuse real-world passwords.
- Keep every test contained and obtain written permission if demonstrating to others.

## Useful snippets

**SET landing page path**

```
/usr/share/set/src/html/templates/google/index.html
```

**Example campaign URL format**

```
http://<ATTACKER_IP>:<PORT>#
# e.g. http://192.168.56.101:8080#
```

**Example redirect snippet to add to landing page**

```html
<script>
  // after capturing creds, redirect to the real site
  window.location = "https://account.google.com";
</script>
```

---

## Final checklist
- [ ] GoPhish dashboard running
- [ ] Sending profile created + test email sent
- [ ] Landing page created (SET HTML pasted)
- [ ] Redirect to real site added
- [ ] Email template created + “change links” ticked
- [ ] Campaign created (attacker IP + port in URL)
- [ ] Campaign launched
- [ ] Credentials verified in GoPhish campaign details

---

## Resources

- GoPhish https://getgophish.com/
- Loi Liang Yang https://www.youtube.com/watch?v=dktthMkQF-Q



*Ethics reminder: this guide is for lab learning only. Always obtain permission before testing real systems.*
