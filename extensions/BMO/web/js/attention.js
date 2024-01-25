var auto_refresh_interval_id = null;

function updateAutoRefresh() {
  let auto_refresh_element = document.querySelector("#auto_refresh");
  if (auto_refresh_element.checked) {
    setCookie("attention_auto_refresh", 1);
    auto_refresh_interval_id = setInterval(() => {
      window.location.reload();
    }, 600000);
  } else {
    setCookie("attention_auto_refresh", 0);
    clearInterval(auto_refresh_interval_id);
  }
}

function setCookie(name, value) {
  document.cookie = name + "=" + (value ? 1 : 0) + "; path=/; SameSite=Lax";
}

function getCookie(name) {
  let nameEQ = name + "=";
  let ca = document.cookie.split(";");
  for (let i = 0; i < ca.length; i++) {
    let c = ca[i];
    while (c.charAt(0) == " ") {
      c = c.substring(1, c.length);
    }
    if (c.indexOf(nameEQ) == 0) {
      return c.substring(nameEQ.length, c.length);
    }
  }
  return null;
}

function updateFavIcon() {
  let count = Number(document.querySelector("#total-bug-count").textContent);
  if (count == 0) return;

  const linkEl = document.querySelector("link[rel*=icon]");
  const faviconImg = document.querySelector("#favicon-base");
  const faviconSize = 32;
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  const img = document.createElement("img");
  img.src = linkEl.href;

  img.onload = () => {
    canvas.width = faviconSize;
    canvas.height = faviconSize;
    ctx.drawImage(faviconImg, 0, 0, faviconSize, faviconSize);
    ctx.font = `bold ${faviconSize / 1.5}px monospace`;
    ctx.lineWidth = 3;

    let metrics = ctx.measureText(count);
    if (metrics.width > faviconSize - 1) {
      count = "xx";
      metrics = ctx.measureText(count);
    }
    const x = faviconSize - metrics.width - 1;
    const y =
      1 + metrics.actualBoundingBoxAscent + metrics.actualBoundingBoxDescent;

    ctx.strokeStyle = "#ffffff";
    ctx.strokeText(count, x, y);
    ctx.fillStyle = "#000000";
    ctx.fillText(count, x, y);

    linkEl.href = canvas.toDataURL("image/png");
  };
}

window.addEventListener("load", () => {
  let auto_refresh_element = document.querySelector("#auto_refresh");
  if (getCookie("attention_auto_refresh") == 1) {
    auto_refresh_element.checked = true;
  }
  updateAutoRefresh();
  auto_refresh_element.onchange(updateAutoRefresh);

  updateFavIcon();

  // table sorting

  const getCellValue = (tr, idx) =>
    Number(tr.children[idx].dataset.value) ||
    tr.children[idx].dataset.value ||
    tr.children[idx].innerText ||
    tr.children[idx].textContent;

  const comparer = (idx, asc) => (a, b) =>
    ((v1, v2) =>
      v1 !== "" && v2 !== "" && !isNaN(v1) && !isNaN(v2)
        ? v1 - v2
        : v1.toString().localeCompare(v2))(
      getCellValue(asc ? a : b, idx),
      getCellValue(asc ? b : a, idx),
    );

  document.querySelectorAll("table.bug-list th").forEach((th) =>
    th.addEventListener("click", () => {
      const table = th.closest("table");
      let asc = !th.classList.contains("order-a");
      if (asc) {
        th.classList.remove("order-d");
        th.classList.add("order-a");
      } else {
        th.classList.remove("order-a");
        th.classList.add("order-d");
      }
      table
        .querySelectorAll("th.sort-col")
        .forEach((th) => th.classList.remove("sort-col"));
      th.classList.add("sort-col");
      Array.from(table.querySelectorAll("tbody tr"))
        .sort(comparer(Array.from(th.parentNode.children).indexOf(th), asc))
        .forEach((tr) => table.querySelector("tbody").appendChild(tr));
    }),
  );
});
