/**
 * ETUBU Custom Modal Picker (Language, Sound Profile, Visual Theme)
 * Works seamlessly across Mobile, Desktop, and Tesla in-car browser.
 */
const Picker = (() => {
  let openMenu = null;
  let openBtn = null;
  let openSelect = null;
  let backdrop = null;
  let ignoreCloseUntil = 0;

  function ensureBackdrop() {
    if (backdrop && document.body.contains(backdrop)) return backdrop;
    backdrop = document.createElement("div");
    backdrop.className = "picker-backdrop";
    backdrop.hidden = true;
    backdrop.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (Date.now() < ignoreCloseUntil) return;
      close();
    });
    document.body.appendChild(backdrop);
    return backdrop;
  }

  function open(btn, menu, select) {
    ensureBackdrop();
    fillMenu(select, menu, btn);
    menu.style.cssText = [
      "position:fixed",
      "z-index:10050",
      "left:50%",
      "top:50%",
      "transform:translate(-50%,-50%)",
      "width:min(380px,calc(100vw - 24px))",
      "max-height:min(72vh,520px)",
      "margin:0",
      "padding:14px 12px",
      "border-radius:18px",
      "border:1px solid rgba(0,240,255,0.3)",
      "background:rgba(10,16,28,0.96)",
      "backdrop-filter:blur(16px)",
      "-webkit-backdrop-filter:blur(16px)",
      "box-shadow:0 24px 64px rgba(0,0,0,0.8), 0 0 32px rgba(0,240,255,0.15)",
      "overflow-x:hidden",
      "overflow-y:auto",
      "display:flex",
      "flex-direction:column",
      "gap:6px",
    ].join(";");

    if (backdrop) {
      backdrop.style.cssText =
        "position:fixed;inset:0;z-index:10040;background:rgba(2,6,16,0.78);backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px);display:block";
      backdrop.hidden = false;
    }
    menu.hidden = false;
    openMenu = menu;
    openBtn = btn;
    openSelect = select;
    btn.setAttribute("aria-expanded", "true");
    document.body.classList.add("picker-open");
    ignoreCloseUntil = Date.now() + 350;
  }

  function close() {
    if (openMenu) {
      openMenu.hidden = true;
      openMenu.style.display = "none";
      openMenu = null;
    }
    if (openBtn) {
      openBtn.setAttribute("aria-expanded", "false");
      openBtn = null;
    }
    openSelect = null;
    if (backdrop) {
      backdrop.hidden = true;
      backdrop.style.display = "none";
    }
    document.body.classList.remove("picker-open");
  }

  function optionList(select) {
    const items = [];
    Array.from(select.children).forEach((child) => {
      if (child.tagName === "OPTGROUP") {
        items.push({ type: "group", label: child.label || "" });
        Array.from(child.children).forEach((opt) => {
          if (opt.tagName === "OPTION") {
            items.push({
              type: "option",
              value: opt.value,
              label: opt.textContent,
              disabled: opt.disabled,
            });
          }
        });
      } else if (child.tagName === "OPTION") {
        items.push({
          type: "option",
          value: child.value,
          label: child.textContent,
          disabled: child.disabled,
        });
      }
    });
    return items;
  }

  function selectedLabel(select) {
    const opt = select.selectedOptions?.[0] || select.options[select.selectedIndex];
    return opt && opt.textContent ? opt.textContent : "-";
  }

  function fillMenu(select, menu, btn) {
    menu.innerHTML = "";
    const title = document.createElement("div");
    title.className = "picker-title";
    title.style.cssText =
      "font-family:var(--font-display,sans-serif);font-size:13px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;color:#00f0ff;padding:4px 8px 10px 8px;border-bottom:1px solid rgba(255,255,255,0.08);margin-bottom:6px;text-align:center;";

    const titleKey = btn.dataset.pickerTitleKey;
    title.textContent =
      (titleKey && typeof I18n !== "undefined" ? I18n.t(titleKey) : null) ||
      btn.dataset.pickerTitle ||
      (typeof I18n !== "undefined" ? I18n.t("pickerSelect") : "Seçiniz");
    menu.appendChild(title);

    const items = optionList(select);
    if (!items.length) {
      const empty = document.createElement("div");
      empty.className = "picker-empty";
      empty.textContent =
        typeof I18n !== "undefined" ? I18n.t("pickerEmpty") : "Seçenek yok";
      empty.style.cssText = "color:#8899aa;font-size:13px;text-align:center;padding:16px;";
      menu.appendChild(empty);
      return;
    }

    items.forEach((item) => {
      if (item.type === "group") {
        const g = document.createElement("div");
        g.className = "picker-group";
        g.textContent = item.label;
        g.style.cssText =
          "font-size:11px;font-weight:700;letter-spacing:0.06em;color:rgba(255,255,255,0.45);text-transform:uppercase;padding:8px 8px 2px 8px;margin-top:4px;";
        menu.appendChild(g);
        return;
      }
      const b = document.createElement("button");
      b.type = "button";
      b.className = "picker-option";
      b.textContent = item.label;
      const isSel = item.value === select.value;
      if (isSel) b.classList.add("is-selected");
      if (item.disabled) {
        b.disabled = true;
        b.classList.add("is-disabled");
      }
      b.style.cssText = [
        "display:flex",
        "align-items:center",
        "justify-content:space-between",
        "width:100%",
        "padding:10px 14px",
        "border-radius:10px",
        "border:1px solid " + (isSel ? "rgba(0,240,255,0.55)" : "rgba(255,255,255,0.06)"),
        "background:" + (isSel ? "linear-gradient(135deg,rgba(0,240,255,0.18),rgba(0,119,255,0.12))" : "rgba(255,255,255,0.03)"),
        "color:" + (isSel ? "#00f0ff" : "#e6f0ff"),
        "font-family:inherit",
        "font-size:14px",
        "font-weight:" + (isSel ? "700" : "500"),
        "cursor:pointer",
        "transition:all 0.15s ease",
        "text-align:left",
      ].join(";");

      b.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (item.disabled) return;
        select.value = item.value;
        select.dispatchEvent(new Event("change", { bubbles: true }));
        btn.textContent = item.label;
        close();
      });
      menu.appendChild(b);
    });
  }

  function resolveTitle(titleOrKey) {
    if (!titleOrKey) return "";
    if (typeof titleOrKey === "function") return titleOrKey() || "";
    if (typeof I18n !== "undefined") return I18n.t(titleOrKey);
    return String(titleOrKey);
  }

  function enhance(select, titleOrKey) {
    if (!select || select.dataset.picker === "1") return;
    select.dataset.picker = "1";

    const wrap = document.createElement("div");
    wrap.className = "picker-wrap";
    select.parentNode.insertBefore(wrap, select);
    wrap.appendChild(select);
    select.classList.add("picker-native");
    select.tabIndex = -1;
    select.setAttribute("aria-hidden", "true");
    select.style.display = "none";

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "picker-btn";
    btn.setAttribute("aria-haspopup", "listbox");
    btn.setAttribute("aria-expanded", "false");
    if (typeof titleOrKey === "string" && titleOrKey && !titleOrKey.includes(" ")) {
      btn.dataset.pickerTitleKey = titleOrKey;
    }
    const title = resolveTitle(titleOrKey);
    if (title) btn.dataset.pickerTitle = title;
    btn.textContent = selectedLabel(select);
    wrap.appendChild(btn);

    const menu = document.createElement("div");
    menu.className = "picker-menu";
    menu.hidden = true;
    menu.setAttribute("role", "listbox");
    document.body.appendChild(menu);

    const syncLabel = () => {
      btn.textContent = selectedLabel(select);
      btn.disabled = !!select.disabled;
      wrap.classList.toggle("is-disabled", !!select.disabled);
    };

    const toggle = (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (select.disabled) return;
      if (openMenu === menu) {
        close();
        return;
      }
      open(btn, menu, select);
    };

    btn.addEventListener("click", toggle);
    select.addEventListener("change", syncLabel);

    const mo = new MutationObserver(syncLabel);
    mo.observe(select, { childList: true, subtree: true, characterData: true });

    syncLabel();
    select._pickerSync = syncLabel;
  }

  function refreshAll() {
    document.querySelectorAll(".picker-btn[data-picker-title-key]").forEach((btn) => {
      const key = btn.dataset.pickerTitleKey;
      if (!key) return;
      const label = typeof I18n !== "undefined" ? I18n.t(key) : key;
      btn.dataset.pickerTitle = label;
    });
    document.querySelectorAll("select[data-picker='1']").forEach((sel) => {
      sel._pickerSync?.();
    });
  }

  function init(selectors) {
    ensureBackdrop();
    const map = [
      ["#voiceSelect", "voiceTheme"],
      ["#visualSelect", "visualTheme"],
      ["#langSelect", "langLabel"],
      ["#dockLangSelect", "langLabel"],
    ];
    (selectors || map.map((x) => x[0])).forEach((sel, i) => {
      const el = typeof sel === "string" ? document.querySelector(sel) : sel;
      const entry = map.find((m) => m[0] === sel) || map[i];
      if (el) enhance(el, entry?.[1]);
    });

    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") close();
    });
    window.addEventListener("resize", () => {
      if (openMenu) close();
    });
  }

  return { init, refreshAll, close, enhance };
})();

try {
  window.Picker = Picker;
  window.SoundPicker = Picker;
} catch (_) {}
