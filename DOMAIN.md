# Attach healynks.app to Healynks

You own **healynks.app** (Cloudflare Registrar). Checked 4 October 2026: `https://healynks.app/` and `https://healynks.app/login` return Healynks HTML (HTTP 200). `https://www.healynks.app/` redirects to `https://healynks.app/`.

Search uses **https://healynks.app** as the canonical origin (`HEALYNK_CANONICAL_ORIGIN` in `server/seo.ts`, also written in `web/index.html`, `web/robots.txt`, and `web/sitemap.xml`). Switch that constant to `https://healynks.app` once curl shows the domain returns Healynks HTML — that is already the case. If the domain later stops serving the app, point the constant and those files at the Render host below so crawlers are not sent to a dead host.

The Render hostname remains a working fallback:

**https://telemedicine-server-l2bj.onrender.com**

- Login: https://telemedicine-server-l2bj.onrender.com/login
- Patient signup: https://telemedicine-server-l2bj.onrender.com/signup
- Doctor and nurse-agency signup: https://telemedicine-server-l2bj.onrender.com/join

That host is HTTPS and serves the Flutter web app and the API. The custom domain is attached to the Render web service **telemedicine-server** only.

## 1. Add the domain in Render

1. Open the [Render dashboard](https://dashboard.render.com/).
2. Open the web service **telemedicine-server** (hostname `telemedicine-server-l2bj.onrender.com`).
3. Go to **Settings → Custom Domains**.
4. Click **Add Custom Domain**.
5. Enter `healynks.app` and save.
6. Adding the apex also adds `www.healynks.app` (and the other way around), with a redirect between them. If `www.healynks.app` is not listed, click **Add Custom Domain** again and enter `www.healynks.app`.

Render shows the same DNS target on that page. It is `telemedicine-server-l2bj.onrender.com`. Do not type an IP address.

## 2. DNS records in Cloudflare

Cloudflare dashboard → **healynks.app** → **DNS** → **Records** → **Add record**.

Create both records. Leave **Proxy status** as **DNS only** (grey cloud) until Render shows the certificate as issued. An orange cloud sends visitors through Cloudflare and blocks that check.

| Type | Name | Target | Proxy status |
|------|------|--------|----------------|
| CNAME | `@` | `telemedicine-server-l2bj.onrender.com` | DNS only (grey cloud) |
| CNAME | `www` | `telemedicine-server-l2bj.onrender.com` | DNS only (grey cloud) |

`@` is the apex `healynks.app`. Cloudflare flattens that CNAME. On Cloudflare, do not create an A record and do not use a Render load-balancer IP.

Also:

- Delete any **AAAA** records for `@` and `www`. Render does not serve IPv6.
- Set **SSL/TLS → Overview → encryption mode** to **Full**.

Save both records. DNS often updates in a few minutes. Back in Render, open **Custom Domains** and click **Verify** if the rows are still waiting. When both certificates show as issued, you can optionally switch Proxy status to **Proxied** (orange cloud).

Those records are what keep `https://healynks.app` on **telemedicine-server**. Routes `/`, `/login`, `/signup`, and `/join` are served there. Sitemap: `https://healynks.app/sitemap.xml`.
