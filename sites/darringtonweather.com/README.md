# darringtonweather.com

Public Kick watch page for **Darrington Weather TV**.

## Why this page exists

Kick embeds with `autoplay=true&muted=false` still start **muted** in Chrome/Safari/Firefox.
Browsers block unmuted autoplay until there is a user gesture.

This page:

1. Shows a full-viewport **Play with sound** gate (brand-first)
2. Injects the Kick iframe **only after** that click (`autoplay=true&muted=false`)
3. Offers a secondary **Still quiet? Unmute** control that reloads Kick in click-to-play mode if the embed stayed muted

## Deploy

Replace the Cloudflare Pages / static origin document with `index.html`:

```bash
# Example: Cloudflare Pages direct upload, Wrangler, or your moonkin-infra sync
wrangler pages deploy sites/darringtonweather.com --project-name darringtonweather
```

Or paste `index.html` over the current root document on the Cloudflare site that serves `darringtonweather.com`.

## Local preview

```bash
python3 -m http.server 8080 -d sites/darringtonweather.com
# open http://localhost:8080
```
