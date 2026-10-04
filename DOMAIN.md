# Attach a domain to Healynks

The site people can open today is the `https://*.onrender.com` address in the README (Public web app). That link is HTTPS and does not need a custom domain. A custom domain is not live until you buy one and point DNS at Render.

You cannot skip the registrar step from this repo. Buy the name yourself, then attach it in the Render dashboard. Examples to search for, not names this project owns: `healynks.com` or `app.healynks.com`.

## 1. Buy a domain

Buy any domain at a registrar:

- [Cloudflare Registrar](https://www.cloudflare.com/products/registrar/)
- [Namecheap](https://www.namecheap.com/)
- [Google Domains](https://domains.google/) (registration now goes through Squarespace)

Use the apex (`healynks.com`) if you want the shortest link, or a subdomain (`app.healynks.com`) if the apex already has another site.

## 2. Add it on the Render static site

1. Open the [Render dashboard](https://dashboard.render.com/).
2. Open the service that serves the Flutter app. Prefer the **healynks-web** static site. If that service is not in the dashboard yet, use **telemedicine-server** (it serves the same web build at its root, and `/health` stays the API health check).
3. Go to **Settings → Custom Domains**.
4. Choose **Add Custom Domain** and enter the domain you bought, for example `app.healynks.com` or `healynks.com`.
5. Render shows the DNS records to create. Copy those values. They are the source of truth; do not guess an IP from an old blog post.

## 3. Set the DNS records Render shows

At the registrar (or wherever DNS is hosted):

- **Subdomain** such as `app.healynks.com`: add the **CNAME** Render shows. It usually points at the service hostname (`healynks-web.onrender.com`).
- **Apex** such as `healynks.com`: add the **A** or **ALIAS / ANAME** record Render shows. Cloudflare can use CNAME flattening on the apex if Render tells you to use a CNAME.

Remove any old A or CNAME on that same host name so only Render’s records remain. Save, then wait for DNS to propagate (often a few minutes, sometimes longer).

## 4. Wait for the certificate

Back on the Render custom domain row, wait until the domain shows as verified and the certificate is issued. Render requests the HTTPS certificate for you. When it is verified, `https://` on your domain opens the Healynks login.

Routes `/`, `/login`, `/signup`, and `/join` are rewritten to `index.html` on the static site, so those links keep working on the custom domain.

Patient registration is `/signup`. Doctors and nurse agencies register at `/join`.
