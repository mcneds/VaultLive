# Vault Live

Static wrapper site for Obsidian exports.

## What it does

- Serves a root `index.html` that lists exported sites by folder.
- Adds a small floating switcher inside each exported HTML page so you can jump back to the directory or into another site.
- Keeps everything static, so Cloudflare Pages can deploy the repo directly from GitHub.

## Refresh the wrapper after adding new exports

Run this from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-site-wrapper.ps1
```

That updates `site-index.json` and injects the shared wrapper script into each exported page.

## Cloudflare Pages

- Connect the `VaultLive` GitHub repo.
- Use `None` as the framework preset.
- Leave the build command empty.
- Set the output directory to `/`.
- Attach your custom subdomain in the Cloudflare Pages dashboard.
