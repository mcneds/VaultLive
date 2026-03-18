(function () {
  "use strict";

  var directory = document.getElementById("site-directory");
  var searchInput = document.getElementById("site-search");
  var siteCount = document.getElementById("site-count");
  var siteUpdated = document.getElementById("site-updated");
  var bootstrapScript =
    document.currentScript ||
    document.querySelector("script[data-wrapper-root][src*='wrapper.js']");

  var root = normalizeRoot(
    directory
      ? "."
      : bootstrapScript && bootstrapScript.dataset.wrapperRoot
        ? bootstrapScript.dataset.wrapperRoot
        : "."
  );

  var repoRootUrl = getRepoRootUrl(root);
  var isDirectoryPage = !!directory;

  if (!isDirectoryPage) {
    ensureStylesheet();
  }

  fetchManifest()
    .then(function (manifest) {
      if (isDirectoryPage) {
        renderDirectory(manifest);
      } else {
        renderSwitcher(manifest);
      }
    })
    .catch(function (error) {
      console.error("Vault wrapper could not load the site manifest.", error);

      if (isDirectoryPage) {
        directory.replaceChildren(
          createEmptyState(
            "The site directory could not be loaded.",
            "Run scripts/build-site-wrapper.ps1 to regenerate site-index.json, then refresh the page."
          )
        );
      }
    });

  function normalizeRoot(value) {
    if (!value || value === "." || value === "./") {
      return ".";
    }

    return String(value).replace(/\\/g, "/").replace(/\/+$/, "");
  }

  function getRepoRootUrl(baseRoot) {
    var pageUrl = new URL(window.location.href);

    if (baseRoot === ".") {
      return new URL("./", pageUrl);
    }

    return new URL(baseRoot.replace(/\/+$/, "") + "/", pageUrl);
  }

  function toRepoUrl(relativePath) {
    var cleanedPath = String(relativePath || "")
      .replace(/^\/+/, "")
      .replace(/\\/g, "/");

    return new URL(cleanedPath, repoRootUrl).href;
  }

  function fetchManifest() {
    return fetch(toRepoUrl("site-index.json"), { cache: "no-store" }).then(function (response) {
      if (!response.ok) {
        throw new Error("Manifest request failed with status " + response.status + ".");
      }

      return response.json();
    });
  }

  function ensureStylesheet() {
    if (document.querySelector("link[data-vault-wrapper-style='true']")) {
      return;
    }

    var link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = toRepoUrl("assets/wrapper.css");
    link.dataset.vaultWrapperStyle = "true";
    document.head.appendChild(link);
  }

  function normalizePathname(pathname) {
    return decodeURIComponent(String(pathname || ""))
      .replace(/\\/g, "/")
      .replace(/^\/+/, "")
      .replace(/\/+$/, "");
  }

  function formatCount(value, noun) {
    return value + " " + noun + (value === 1 ? "" : "s");
  }

  function toArray(value) {
    if (Array.isArray(value)) {
      return value.slice();
    }

    if (value && typeof value === "object") {
      return [value];
    }

    return [];
  }

  function formatDate(value) {
    var date = new Date(value);

    if (Number.isNaN(date.valueOf())) {
      return "Manifest timestamp unavailable";
    }

    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short"
    }).format(date);
  }

  function renderDirectory(manifest) {
    var sites = toArray(manifest.sites);
    var query = "";

    if (siteUpdated) {
      siteUpdated.textContent = "Updated " + formatDate(manifest.generatedAt);
    }

    if (searchInput) {
      searchInput.addEventListener("input", function () {
        query = searchInput.value.trim().toLowerCase();
        draw();
      });
    }

    draw();

    function draw() {
      var filtered = sites.filter(function (site) {
        if (!query) {
          return true;
        }

        return [
          site.name,
          site.collection,
          site.pageTitle,
          site.description
        ].join(" ").toLowerCase().indexOf(query) !== -1;
      });

      if (siteCount) {
        siteCount.textContent = formatCount(filtered.length, "site");
      }

      directory.replaceChildren();

      if (!filtered.length) {
        directory.appendChild(
          createEmptyState(
            "No sites match that search.",
            "Try another folder name, page title, or topic keyword."
          )
        );
        return;
      }

      var groups = new Map();

      filtered.forEach(function (site) {
        var key = site.collection || "Root";

        if (!groups.has(key)) {
          groups.set(key, []);
        }

        groups.get(key).push(site);
      });

      groups.forEach(function (groupSites, groupName) {
        directory.appendChild(createGroup(groupName, groupSites));
      });
    }
  }

  function createGroup(groupName, groupSites) {
    var section = document.createElement("section");
    section.className = "vault-wrapper-group";

    var header = document.createElement("div");
    header.className = "vault-wrapper-group-header";

    var label = document.createElement("span");
    label.className = "vault-wrapper-group-label";
    label.textContent = groupName === "Root" ? "Top Level" : groupName;

    var title = document.createElement("h2");
    title.textContent = groupName === "Root" ? "Standalone sites" : groupName;

    var count = document.createElement("span");
    count.className = "vault-wrapper-card-count";
    count.textContent = formatCount(groupSites.length, "site");

    var headingCopy = document.createElement("div");
    headingCopy.append(label, title);

    header.append(headingCopy, count);
    section.appendChild(header);

    var grid = document.createElement("div");
    grid.className = "vault-wrapper-grid";

    groupSites.forEach(function (site) {
      grid.appendChild(createSiteCard(site));
    });

    section.appendChild(grid);
    return section;
  }

  function createSiteCard(site) {
    var article = document.createElement("article");
    article.className = "vault-wrapper-card";

    var meta = document.createElement("div");
    meta.className = "vault-wrapper-card-meta";

    var collection = document.createElement("span");
    collection.textContent = "Static export";

    var count = document.createElement("span");
    count.textContent = formatCount(site.pageCount || 0, "page");

    meta.append(collection, count);

    var heading = document.createElement("h3");
    heading.textContent = site.name;

    var subtitle = document.createElement("p");
    subtitle.className = "vault-wrapper-card-subtitle";
    subtitle.textContent = site.pageTitle || "Open the exported site";

    var description = document.createElement("p");
    description.className = "vault-wrapper-card-description";
    description.textContent = site.description || "This export is ready to open.";

    var link = document.createElement("a");
    link.className = "vault-wrapper-card-link";
    link.href = toRepoUrl(site.entry);
    link.textContent = "Open site";

    article.append(meta, heading, subtitle, description, link);
    return article;
  }

  function createEmptyState(titleText, bodyText) {
    var wrapper = document.createElement("div");
    wrapper.className = "vault-wrapper-empty";

    var title = document.createElement("h2");
    title.textContent = titleText;

    var body = document.createElement("p");
    body.textContent = bodyText;

    wrapper.append(title, body);
    return wrapper;
  }

  function renderSwitcher(manifest) {
    var sites = toArray(manifest.sites);

    if (!sites.length || document.querySelector(".vault-wrapper-switcher")) {
      return;
    }

    var currentPath = normalizePathname(window.location.pathname);

    var currentSite = sites.find(function (site) {
      var entryPath = normalizePathname(site.entry);
      var rootPath = normalizePathname(site.root);

      return (
        currentPath === entryPath ||
        currentPath.endsWith("/" + entryPath) ||
        (rootPath && currentPath.indexOf(rootPath + "/") !== -1)
      );
    }) || null;

    var switcher = document.createElement("div");
    switcher.className = "vault-wrapper-switcher";
    switcher.dataset.open = "false";

    var toggle = document.createElement("button");
    toggle.className = "vault-wrapper-toggle";
    toggle.type = "button";
    toggle.setAttribute("aria-expanded", "false");
    toggle.textContent = currentSite ? "Sites: " + currentSite.name : "Sites";

    var panel = document.createElement("aside");
    panel.className = "vault-wrapper-panel";

    var panelHeader = document.createElement("div");
    panelHeader.className = "vault-wrapper-panel-header";

    var panelTitle = document.createElement("h2");
    panelTitle.className = "vault-wrapper-panel-title";
    panelTitle.textContent = currentSite ? currentSite.name : "Site switcher";

    var panelCopy = document.createElement("p");
    panelCopy.className = "vault-wrapper-panel-copy";
    panelCopy.textContent = currentSite
      ? "Jump back to the directory or move across exported sites."
      : "Open another exported site or return to the directory.";

    panelHeader.append(panelTitle, panelCopy);

    var homeLink = document.createElement("a");
    homeLink.className = "vault-wrapper-home-link";
    homeLink.href = repoRootUrl.href;
    homeLink.textContent = "Back to directory";

    var siteList = document.createElement("div");
    siteList.className = "vault-wrapper-site-list";

    sites.forEach(function (site) {
      siteList.appendChild(createSwitcherLink(site, currentSite));
    });

    panel.append(panelHeader, homeLink, siteList);
    switcher.append(toggle, panel);
    document.body.appendChild(switcher);

    toggle.addEventListener("click", function () {
      var isOpen = switcher.dataset.open === "true";
      switcher.dataset.open = isOpen ? "false" : "true";
      toggle.setAttribute("aria-expanded", String(!isOpen));
    });

    document.addEventListener("click", function (event) {
      if (!switcher.contains(event.target)) {
        switcher.dataset.open = "false";
        toggle.setAttribute("aria-expanded", "false");
      }
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        switcher.dataset.open = "false";
        toggle.setAttribute("aria-expanded", "false");
      }
    });
  }

  function createSwitcherLink(site, currentSite) {
    var link = document.createElement("a");
    var isCurrent = currentSite && currentSite.entry === site.entry;
    link.className = "vault-wrapper-site-link" + (isCurrent ? " is-current" : "");
    link.href = toRepoUrl(site.entry);

    var copy = document.createElement("span");
    copy.className = "vault-wrapper-site-copy";

    var collection = document.createElement("span");
    collection.className = "vault-wrapper-site-collection";
    collection.textContent = site.collection || "Root";

    var title = document.createElement("span");
    title.className = "vault-wrapper-site-title";
    title.textContent = site.name;

    var subtitle = document.createElement("span");
    subtitle.className = "vault-wrapper-panel-copy";
    subtitle.textContent = site.pageTitle || "Open site";

    copy.append(collection, title, subtitle);

    var label = document.createElement("span");
    label.className = "vault-wrapper-site-label";
    label.textContent = isCurrent ? "Current" : "Visit";

    link.append(copy, label);
    return link;
  }
})();