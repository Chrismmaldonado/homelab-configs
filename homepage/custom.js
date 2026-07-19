(() => {
  const enhance = () => {
    const layout = document.querySelector("#layout-groups");
    if (!layout) return;

    if (!document.querySelector("#command-header")) {
      const header = document.createElement("section");
      header.id = "command-header";
      header.innerHTML = `
        <div class="command-copy">
          <span class="command-kicker">HOMELAB2</span>
          <strong>Local services</strong>
        </div>
        <div class="command-health"><i></i><span>online</span></div>`;
      layout.parentNode.insertBefore(header, layout);
    }

    document.querySelectorAll(".services-group").forEach((group) => {
      const title = group.querySelector(".service-group-name, h2");
      if (!title) return;
      const slug = title.textContent.trim().toLowerCase().replace(/\s+/g, "-");
      group.classList.add(`group-${slug}`);
    });

    document.querySelectorAll(".service-card").forEach((card) => {
      const nameEl = card.querySelector(".service-name");
      const name = nameEl
        ? [...nameEl.childNodes].find((n) => n.nodeType === Node.TEXT_NODE)?.textContent?.trim()
        : "";
      if (!name) return;
      card.dataset.service = name.toLowerCase();
      if (name === "Maintenant") card.classList.add("featured-service");
    });

    const input = document.querySelector("#search-input, input[type=\"text\"]");
    if (input) input.placeholder = "Search…";
  };

  document.addEventListener("DOMContentLoaded", enhance);
  new MutationObserver(enhance).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  setTimeout(enhance, 400);
})();
