(function () {
  "use strict";

  const state = {
    manifest: null,
    current: null
  };

  init().catch((error) => {
    console.error("VaultLive failed to initialize:", error);
    document.body.innerHTML = `
      <main style="padding:24px;font-family:Arial,sans-serif">
        <h1>VaultLive failed to load</h1>
        <p>${escapeHtml(error && error.message ? error.message : String(error))}</p>
      </main>
    `;
  });

  async function init() {
    state.manifest = await loadManifest();
    mountShell();
    window.addEventListener("popstate", renderFromUrl);
    renderFromUrl();
  }

  async function loadManifest() {
    const response = await fetch("/site-index.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error("Could not load site-index.json (" + response.status + ")");
    }
    return response.json();
  }

  function mountShell() {
    document.title = "Vault Live";
    document.body.innerHTML = `
      <div class="vl-app">
        <header class="vl-topbar">
          <a class="vl-brand" href="/">VaultLive</a>

          <button id="vl-directory-btn" class="vl-btn" type="button">Directory</button>

          <select id="vl-site-select" class="vl-select">
            <option value="">Select export</option>
          </select>

          <div class="vl-grow"></div>

          <div id="vl-current-label" class="vl-current-label"></div>

          <a id="vl-open-raw" class="vl-btn" target="_blank" rel="noopener noreferrer">Open raw</a>
        </header>

        <main id="vl-root"></main>
      </div>
    `;

    injectStyles();

    const select = document.getElementById("vl-site-select");
    const dirBtn = document.getElementById("vl-directory-btn");

    getSites().forEach((site) => {
      const option = document.createElement("option");
      option.value = site.id;
      option.textContent = site.name || site.pageTitle || site.entry || site.id;
      select.appendChild(option);
    });

    select.addEventListener("change", () => {
      const site = findSite(select.value);
      if (!site) return;
      goToSite(site);
    });

    dirBtn.addEventListener("click", () => {
      history.pushState({}, "", "/");
      renderFromUrl();
    });
  }

  function renderFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const siteId = params.get("site");
    const root = document.getElementById("vl-root");
    const label = document.getElementById("vl-current-label");
    const rawLink = document.getElementById("vl-open-raw");
    const select = document.getElementById("vl-site-select");

    if (!siteId) {
      state.current = null;
      select.value = "";
      label.textContent = "Directory";
      rawLink.href = "/";
      rawLink.style.visibility = "hidden";
      renderDirectory(root);
      return;
    }

    const site = findSite(siteId);
    if (!site) {
      state.current = null;
      select.value = "";
      label.textContent = "Directory";
      rawLink.href = "/";
      rawLink.style.visibility = "hidden";
      renderDirectory(root, "That export was not found.");
      return;
    }

    state.current = site;
    select.value = site.id;
    label.textContent = site.name || site.pageTitle || site.entry;
    rawLink.href = "/" + stripLeadingSlash(site.entry);
    rawLink.style.visibility = "visible";

    renderViewer(root, site);
  }

  function renderDirectory(root, message) {
    const sites = getSites();

    root.innerHTML = `
      <section class="vl-directory">
        <div class="vl-hero">
          <h1>VaultLive</h1>
          <p>Open standalone Obsidian HTML exports inside a minimal shell.</p>
          <input id="vl-search" class="vl-search" type="search" placeholder="Search exports">
        </div>

        ${message ? `<div class="vl-message">${escapeHtml(message)}</div>` : ""}

        <div id="vl-grid" class="vl-grid"></div>
      </section>
    `;

    const search = document.getElementById("vl-search");
    const grid = document.getElementById("vl-grid");

    function draw() {
      const q = (search.value || "").trim().toLowerCase();
      const filtered = sites.filter((site) => {
        const text = [
          site.name,
          site.pageTitle,
          site.description,
          site.entry,
          site.collection
        ].join(" ").toLowerCase();
        return !q || text.includes(q);
      });

      grid.innerHTML = "";

      if (!filtered.length) {
        grid.innerHTML = `
          <article class="vl-card">
            <h3>No matches</h3>
            <p>Try another search term.</p>
          </article>
        `;
        return;
      }

      filtered.forEach((site) => {
        const card = document.createElement("article");
        card.className = "vl-card";
        card.innerHTML = `
          <div class="vl-card-meta">
            <span>${escapeHtml(site.collection || "Export")}</span>
            <span>single HTML</span>
          </div>
          <h3>${escapeHtml(site.name || site.pageTitle || site.id)}</h3>
          <p>${escapeHtml(site.description || site.pageTitle || site.entry)}</p>
          <div class="vl-card-actions">
            <button class="vl-btn vl-btn-primary" type="button">Open in shell</button>
            <a class="vl-btn" href="/${escapeAttr(stripLeadingSlash(site.entry))}" target="_blank" rel="noopener noreferrer">Open raw</a>
          </div>
        `;

        card.querySelector("button").addEventListener("click", () => goToSite(site));
        grid.appendChild(card);
      });
    }

    search.addEventListener("input", draw);
    draw();
  }

  function renderViewer(root, site) {
    root.innerHTML = `
      <section class="vl-view">
        <iframe
          id="vl-frame"
          class="vl-frame"
          src="/${escapeAttr(stripLeadingSlash(site.entry))}"
          loading="eager"
          referrerpolicy="strict-origin-when-cross-origin"
        ></iframe>
      </section>
    `;

    const frame = document.getElementById("vl-frame");

    frame.addEventListener("load", () => {
      try {
        const title = frame.contentDocument && frame.contentDocument.title;
        document.title = (title || site.name || "Vault Live") + " - Vault Live";
      } catch (_) {
        document.title = (site.name || "Vault Live") + " - Vault Live";
      }
    });
  }

  function goToSite(site) {
    const url = new URL(window.location.href);
    url.search = "";
    url.searchParams.set("site", site.id);
    history.pushState({}, "", url);
    renderFromUrl();
  }

  function getSites() {
    const sites = Array.isArray(state.manifest && state.manifest.sites)
      ? state.manifest.sites.slice()
      : [];

    return sites.map((site) => ({
      ...site,
      entry: site.entry || inferEntry(site)
    })).filter((site) => site.entry && /\.html?$/i.test(site.entry));
  }

  function inferEntry(site) {
    if (site.entry) return site.entry;
    if (Array.isArray(site.pages) && site.pages.length) {
      return site.pages[0].path || "";
    }
    return "";
  }

  function findSite(id) {
    return getSites().find((site) => site.id === id) || null;
  }

  function stripLeadingSlash(value) {
    return String(value || "").replace(/^\/+/, "");
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function escapeAttr(value) {
    return escapeHtml(value);
  }

  function injectStyles() {
    if (document.getElementById("vl-inline-styles")) return;

    const style = document.createElement("style");
    style.id = "vl-inline-styles";
    style.textContent = `
      :root {
        --vl-bg: #0f141a;
        --vl-panel: rgba(20, 26, 34, 0.9);
        --vl-card: rgba(255,255,255,0.04);
        --vl-border: rgba(255,255,255,0.08);
        --vl-text: #eef4f7;
        --vl-muted: rgba(238,244,247,0.68);
        --vl-accent: #295a64;
        --vl-shadow: 0 18px 40px rgba(0,0,0,0.28);
        --vl-topbar-h: 56px;
      }

      html, body {
        margin: 0;
        min-height: 100%;
        background: var(--vl-bg);
        color: var(--vl-text);
        font-family: Inter, Arial, sans-serif;
      }

      .vl-topbar {
        position: fixed;
        inset: 0 0 auto 0;
        z-index: 9999;
        height: var(--vl-topbar-h);
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 0 12px;
        background: var(--vl-panel);
        border-bottom: 1px solid var(--vl-border);
        backdrop-filter: blur(12px);
        box-shadow: var(--vl-shadow);
      }

      .vl-brand {
        color: var(--vl-text);
        text-decoration: none;
        font-weight: 700;
      }

      .vl-btn,
      .vl-select,
      .vl-search {
        height: 36px;
        border-radius: 10px;
        border: 1px solid var(--vl-border);
        background: rgba(255,255,255,0.05);
        color: var(--vl-text);
        padding: 0 12px;
        box-sizing: border-box;
        font: inherit;
      }

      .vl-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        text-decoration: none;
        cursor: pointer;
      }

      .vl-btn-primary {
        background: var(--vl-accent);
      }

      .vl-grow {
        flex: 1 1 auto;
      }

      .vl-current-label {
        color: var(--vl-muted);
        font-size: 0.92rem;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: 28vw;
      }

      .vl-directory {
        padding: calc(var(--vl-topbar-h) + 24px) 24px 24px;
        max-width: 1200px;
        margin: 0 auto;
      }

      .vl-hero {
        display: grid;
        gap: 12px;
        padding: 24px;
        border: 1px solid var(--vl-border);
        border-radius: 20px;
        background: var(--vl-card);
        box-shadow: var(--vl-shadow);
        margin-bottom: 18px;
      }

      .vl-hero h1 {
        margin: 0;
        font-size: clamp(2rem, 4vw, 3.2rem);
        line-height: 0.96;
      }

      .vl-hero p {
        margin: 0;
        color: var(--vl-muted);
      }

      .vl-search {
        width: min(420px, 100%);
      }

      .vl-message {
        padding: 14px 16px;
        border: 1px solid var(--vl-border);
        border-radius: 14px;
        background: var(--vl-card);
        margin-bottom: 18px;
      }

      .vl-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
        gap: 14px;
      }

      .vl-card {
        display: grid;
        gap: 12px;
        padding: 16px;
        border: 1px solid var(--vl-border);
        border-radius: 18px;
        background: var(--vl-card);
        box-shadow: var(--vl-shadow);
      }

      .vl-card h3,
      .vl-card p {
        margin: 0;
      }

      .vl-card p {
        color: var(--vl-muted);
        line-height: 1.5;
      }

      .vl-card-meta {
        display: flex;
        justify-content: space-between;
        gap: 10px;
        color: var(--vl-muted);
        font-size: 0.85rem;
      }

      .vl-card-actions {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
      }

      .vl-view {
        position: fixed;
        inset: var(--vl-topbar-h) 0 0 0;
        background: #111;
      }

      .vl-frame {
        width: 100%;
        height: 100%;
        border: 0;
        background: white;
      }

      @media (max-width: 760px) {
        .vl-topbar {
          flex-wrap: wrap;
          height: auto;
          min-height: var(--vl-topbar-h);
          padding-top: 8px;
          padding-bottom: 8px;
        }

        .vl-current-label {
          display: none;
        }

        .vl-view {
          top: 76px;
        }

        .vl-directory {
          padding-top: 100px;
          padding-left: 14px;
          padding-right: 14px;
        }
      }
    `;
    document.head.appendChild(style);
  }
})();