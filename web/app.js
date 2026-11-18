/* NUVIO Agent Store — front-end
   Vanilla JS, no libraries. Reads via a public BSC RPC; writes only through the
   user's own injected wallet (Binance Wallet). Every asset action is confirmed
   by the user in their wallet. No QR-code flow anywhere. */
"use strict";

const STORE = "0x6008c8A96E7b134228000EbdA6F51Fff6a06A786";
const AGENT_ID = "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F";
const USDT = "0x55d398326f99059fF775485246999027B3197955";
const BSC_CHAIN_ID = 56;
const BSC_CHAIN_HEX = "0x38";
const RPC_URLS = [
  "https://bsc-dataseed.binance.org/",
  "https://bsc.publicnode.com/",
  "https://bsc-dataseed1.defibit.io/",
];
let rpcIndex = 0;
const BSCSCAN = "https://bscscan.com";
const ORDER_CREATED_TOPIC0 = "0xb34aee3a4baa1d8e6b7dc504307729f229b4ee905402c3486394a44ab5299489";
const DELIVERY_WINDOW = 3 * 24 * 3600; // seconds
const DELIVERY_DEADLINE = 7 * 24 * 3600; // seconds

// Function selectors (precomputed with `cast sig`).
const SEL = {
  productCount: "0xe0f6ef87",
  products: "0x7acc0b20",
  hasAgentId: "0x4eab3ef2",
  owner: "0x8da5cb5b",
  getOrder: "0xd09ef241",
  orderCount: "0x2453ffa8",
  createOrderBNB: "0x5410f567",
  createOrderUSDT: "0x3d6b4b14",
  approve: "0x095ea7b3",
  allowance: "0xdd62ed3e",
  balanceOf: "0x70a08231",
  tokenOfOwnerByIndex: "0x2f745c59",
  tokenURI: "0xc87b56dd",
  confirmReceipt: "0x843cba13",
  cancelOrder: "0x514fcac7",
  claimRefund: "0x5b7baf64",
};

const STATUS_LABEL = ["Dibayar — menunggu pengiriman", "Terkirim — menunggu konfirmasi kamu", "Selesai", "Dana kembali (refund)", "Dibatalkan"];
const PAY_TOKEN_LABEL = ["BNB", "USDT"];

let account = null;
let agentIdOk = false;
let products = [];
let activeCat = "Semua";

/* ---------- tiny helpers ---------- */
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const shortAddr = (a) => a.slice(0, 6) + "…" + a.slice(-4);
function toast(msg, kind) {
  const t = $("toast");
  t.textContent = msg;
  t.className = "toast" + (kind ? " " + kind : "");
  t.classList.remove("hidden");
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.add("hidden"), 6000);
}
function fmtUnits(v, decimals) {
  const d = BigInt(decimals);
  const base = 10n ** d;
  const int = v / base;
  let frac = (v % base).toString().padStart(Number(d), "0").replace(/0+$/, "");
  if (frac.length > 6) frac = frac.slice(0, 6);
  return frac ? int.toString() + "." + frac : int.toString();
}
const fmtDate = (ts) => new Date(Number(ts) * 1000).toLocaleString("id-ID", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/* ---------- minimal ABI codec ---------- */
function wordUint(v) { return BigInt(v).toString(16).padStart(64, "0"); }
function wordAddr(a) { return "000000000000000000000000" + a.toLowerCase().replace(/^0x/, ""); }
function encodeCall(selector, words) { return selector + words.join(""); }
function u256(data, byteOff) { return BigInt("0x" + data.slice(2 + byteOff * 2, 2 + byteOff * 2 + 64)); }
function addrAt(data, byteOff) { return "0x" + data.slice(2 + byteOff * 2 + 24, 2 + byteOff * 2 + 64); }
function boolAt(data, byteOff) { return u256(data, byteOff) !== 0n; }
function strAt(data, byteOff) {
  const off = Number(u256(data, byteOff));
  const len = Number(u256(data, off));
  const hex = data.slice(2 + off * 2 + 64, 2 + off * 2 + 64 + len * 2);
  const bytes = new Uint8Array(hex.match(/.{2}/g).map((b) => parseInt(b, 16)));
  return new TextDecoder().decode(bytes);
}
function parseProduct(data) {
  return {
    id: Number(u256(data, 0)),
    name: strAt(data, 32),
    category: strAt(data, 64),
    priceBNB: u256(data, 96),
    priceUSDT: u256(data, 128),
    active: boolAt(data, 160),
  };
}
function parseOrder(data) {
  return {
    id: Number(u256(data, 0)),
    buyer: addrAt(data, 32),
    productId: Number(u256(data, 64)),
    payToken: Number(u256(data, 96)),
    amount: u256(data, 128),
    status: Number(u256(data, 160)),
    paidAt: Number(u256(data, 192)),
    deliveredAt: Number(u256(data, 224)),
    deliveryRef: strAt(data, 256),
  };
}

/* ---------- chain reads (public RPC, no wallet needed) ---------- */
async function rpc(method, params) {
  // Try each public BSC endpoint in turn; remember the one that works.
  let lastErr = null;
  for (let i = 0; i < RPC_URLS.length; i++) {
    const url = RPC_URLS[(rpcIndex + i) % RPC_URLS.length];
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", method, params, id: 1 }),
      });
      const j = await res.json();
      if (j.error) throw new Error(j.error.message || "RPC error");
      rpcIndex = RPC_URLS.indexOf(url);
      return j.result;
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr || new Error("Semua endpoint BSC tidak merespons.");
}
async function ethCall(to, data) {
  return rpc("eth_call", [{ to, data }, "latest"]);
}
async function ethCallRetry(to, data) {
  try { return await ethCall(to, data); }
  catch (e) { await new Promise((r) => setTimeout(r, 1000)); return ethCall(to, data); }
}
async function waitReceipt(txHash) {
  for (let i = 0; i < 90; i++) {
    const r = await rpc("eth_getTransactionReceipt", [txHash]).catch(() => null);
    if (r) return r;
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error("Transaksi belum terkonfirmasi setelah 3 menit — cek di BscScan.");
}
function orderIdFromReceipt(receipt) {
  for (const log of receipt.logs || []) {
    if (log.address.toLowerCase() === STORE.toLowerCase() && log.topics[0] === ORDER_CREATED_TOPIC0) {
      return Number(BigInt(log.topics[1]));
    }
  }
  return null;
}

/* ---------- catalogue ---------- */
async function loadProducts() {
  const countHex = await ethCallRetry(STORE, SEL.productCount);
  const count = Number(BigInt(countHex));
  const list = [];
  for (let i = 0; i < count; i++) {
    const data = await ethCallRetry(STORE, SEL.products + wordUint(i));
    list.push(parseProduct(data));
  }
  products = list;
  $("productCountLine").textContent = count + " produk · harga on-chain";
  renderProducts();
}
function productCard(p) {
  const canBuy = account && agentIdOk && p.active;
  return `<article class="card">
    <span class="card-cat">${esc(p.category)}</span>
    <h3>${esc(p.name)}</h3>
    <div class="card-price">
      <span class="bnb">${fmtUnits(p.priceBNB, 18)} BNB</span>
      <span class="usdt">atau ${fmtUnits(p.priceUSDT, 18)} USDT</span>
    </div>
    <div class="card-actions">
      <button class="btn btn-amber" data-buy-bnb="${p.id}" ${canBuy ? "" : "disabled"}>Beli dengan BNB</button>
      <button class="btn" data-buy-usdt="${p.id}" ${canBuy ? "" : "disabled"}>Beli dengan USDT</button>
    </div>
    <span class="card-id">produk #${p.id} · ${p.active ? "tersedia" : "nonaktif"}</span>
  </article>`;
}
function renderProducts() {
  const grid = $("productGrid");
  const list = products.filter((p) => activeCat === "Semua" || p.category === activeCat);
  if (!list.length) { grid.innerHTML = `<p class="loading">Tidak ada produk di kategori ini.</p>`; return; }
  grid.innerHTML = list.map(productCard).join("");
  grid.querySelectorAll("[data-buy-bnb]").forEach((b) => b.addEventListener("click", () => buyBNB(Number(b.dataset.buyBnb))));
  grid.querySelectorAll("[data-buy-usdt]").forEach((b) => b.addEventListener("click", () => buyUSDT(Number(b.dataset.buyUsdt))));
  if (account && !agentIdOk) {
    $("gateNotice").classList.remove("hidden");
    $("gateText").textContent = "Wallet ini belum memegang Agent ID. Klaim Agent ID gratis di aplikasi Binance (Wallet → banner Agent ID), lalu hubungkan lagi wallet kamu.";
  } else if (!account) {
    $("gateNotice").classList.remove("hidden");
    $("gateText").textContent = "Hubungkan wallet untuk memeriksa Agent ID kamu. Agent ID diklaim gratis di aplikasi Binance (Wallet → banner Agent ID).";
  } else {
    $("gateNotice").classList.add("hidden");
  }
}

/* ---------- wallet ---------- */
function provider() {
  if (window.ethereum) return window.ethereum;
  toast("Wallet tidak ditemukan. Buka halaman ini di Binance Wallet (ekstensi browser / aplikasi Binance).", "err");
  return null;
}
async function ensureBsc(eth) {
  const chainId = await eth.request({ method: "eth_chainId" });
  if (parseInt(chainId, 16) === BSC_CHAIN_ID) return true;
  try {
    await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: BSC_CHAIN_HEX }] });
    return true;
  } catch (e) {
    if (e.code === 4902) {
      await eth.request({
        method: "wallet_addEthereumChain",
        params: [{ chainId: BSC_CHAIN_HEX, chainName: "BNB Smart Chain", nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 }, rpcUrls: ["https://bsc-dataseed.binance.org/"], blockExplorerUrls: ["https://bscscan.com"] }],
      });
      return true;
    }
    throw e;
  }
}
async function checkAgentId() {
  const data = await ethCallRetry(AGENT_ID, SEL.balanceOf + wordAddr(account));
  agentIdOk = BigInt(data) > 0n;
  const badge = $("agentBadge");
  badge.classList.remove("hidden");
  if (agentIdOk) {
    badge.classList.remove("no-id");
    badge.textContent = "Agent ID ✓";
    // Best-effort: resolve the .ai name from the token metadata.
    try {
      const tokData = await ethCallRetry(AGENT_ID, SEL.tokenOfOwnerByIndex + wordAddr(account) + wordUint(0));
      const tokenId = BigInt(tokData);
      const uriData = await ethCallRetry(AGENT_ID, SEL.tokenURI + wordUint(tokenId));
      const uri = strAt(uriData, 0);
      const meta = await (await fetch(uri)).json();
      if (meta && meta.name) badge.textContent = "Agent ID ✓ " + meta.name;
    } catch (e) { /* name lookup is optional; badge stays generic */ }
  } else {
    badge.classList.add("no-id");
    badge.textContent = "Tanpa Agent ID";
  }
  renderProducts();
}
async function connect() {
  const eth = provider();
  if (!eth) return;
  try {
    const accounts = await eth.request({ method: "eth_requestAccounts" });
    account = accounts[0];
    await ensureBsc(eth);
    $("connectBtn").textContent = shortAddr(account);
    await checkAgentId();
    renderMyOrders();
    toast("Wallet terhubung: " + shortAddr(account), "ok");
  } catch (e) {
    toast("Gagal menghubungkan wallet: " + (e.message || e), "err");
  }
}
async function sendTx(tx) {
  const eth = provider();
  if (!eth) throw new Error("Wallet tidak ditemukan.");
  return eth.request({ method: "eth_sendTransaction", params: [{ from: account, ...tx }] });
}

/* ---------- buying ---------- */
async function liveProduct(id) {
  const data = await ethCallRetry(STORE, SEL.products + wordUint(id));
  return parseProduct(data);
}
function saveMyOrder(orderId) {
  if (!account) return;
  const key = "nuvio-orders-" + account.toLowerCase();
  const list = JSON.parse(localStorage.getItem(key) || "[]");
  if (!list.includes(orderId)) list.push(orderId);
  localStorage.setItem(key, JSON.stringify(list));
}
async function buyBNB(id) {
  if (!account) { await connect(); if (!account) return; }
  if (!agentIdOk) { toast("Wallet ini belum memegang Agent ID.", "err"); return; }
  try {
    const p = await liveProduct(id);
    toast("Konfirmasi pembayaran " + fmtUnits(p.priceBNB, 18) + " BNB di wallet kamu…");
    const txHash = await sendTx({
      to: STORE,
      value: "0x" + p.priceBNB.toString(16),
      data: SEL.createOrderBNB + wordUint(id),
    });
    toast("Transaksi terkirim — menunggu konfirmasi…");
    const receipt = await waitReceipt(txHash);
    if (receipt.status !== "0x1") throw new Error("Transaksi gagal di chain.");
    let orderId = orderIdFromReceipt(receipt);
    if (orderId === null) {
      const c = await ethCallRetry(STORE, SEL.orderCount);
      orderId = Number(BigInt(c)) - 1;
    }
    saveMyOrder(orderId);
    toast("Order #" + orderId + " berhasil dibuat. Penjual akan menghubungi kamu via Telegram.", "ok");
    showOrder(orderId);
    renderMyOrders();
  } catch (e) {
    toast("Pembelian gagal: " + (e.message || e), "err");
  }
}
async function buyUSDT(id) {
  if (!account) { await connect(); if (!account) return; }
  if (!agentIdOk) { toast("Wallet ini belum memegang Agent ID.", "err"); return; }
  try {
    const p = await liveProduct(id);
    const allowData = await ethCallRetry(USDT, SEL.allowance + wordAddr(account) + wordAddr(STORE));
    if (BigInt(allowData) < p.priceUSDT) {
      toast("Langkah 1/2: approve " + fmtUnits(p.priceUSDT, 18) + " USDT (jumlah persis, tanpa batas) — konfirmasi di wallet…");
      const approveTx = await sendTx({ to: USDT, value: "0x0", data: SEL.approve + wordAddr(STORE) + wordUint(p.priceUSDT) });
      const ar = await waitReceipt(approveTx);
      if (ar.status !== "0x1") throw new Error("Approve USDT gagal.");
    }
    toast("Langkah 2/2: bayar " + fmtUnits(p.priceUSDT, 18) + " USDT — konfirmasi di wallet…");
    const txHash = await sendTx({ to: STORE, value: "0x0", data: SEL.createOrderUSDT + wordUint(id) });
    toast("Transaksi terkirim — menunggu konfirmasi…");
    const receipt = await waitReceipt(txHash);
    if (receipt.status !== "0x1") throw new Error("Transaksi gagal di chain.");
    let orderId = orderIdFromReceipt(receipt);
    if (orderId === null) {
      const c = await ethCallRetry(STORE, SEL.orderCount);
      orderId = Number(BigInt(c)) - 1;
    }
    saveMyOrder(orderId);
    toast("Order #" + orderId + " berhasil dibuat. Penjual akan menghubungi kamu via Telegram.", "ok");
    showOrder(orderId);
    renderMyOrders();
  } catch (e) {
    toast("Pembelian gagal: " + (e.message || e), "err");
  }
}

/* ---------- order tracking ---------- */
function orderCardHtml(o) {
  const p = products.find((x) => x.id === o.productId);
  const token = PAY_TOKEN_LABEL[o.payToken];
  const amount = fmtUnits(o.amount, 18) + " " + token;
  const now = Math.floor(Date.now() / 1000);
  let extra = "";
  if (o.status === 0) {
    const refundAt = o.paidAt + DELIVERY_DEADLINE;
    extra = refundAt > now
      ? `<br>Bisa klaim refund kalau belum dikirim sampai ${fmtDate(refundAt)}.`
      : `<br><strong>Batas pengiriman lewat — kamu bisa klaim refund sekarang.</strong>`;
  } else if (o.status === 1) {
    const releaseAt = o.deliveredAt + DELIVERY_WINDOW;
    extra = `<br>Dana cair otomatis ke penjual pada ${fmtDate(releaseAt)} kalau tidak ada sengketa.`;
  }
  const isBuyer = account && o.buyer.toLowerCase() === account.toLowerCase();
  let actions = "";
  if (isBuyer && o.status === 0) {
    actions += `<button class="btn btn-sm" data-act="cancel" data-id="${o.id}">Batalkan order (refund)</button>`;
    if (now > o.paidAt + DELIVERY_DEADLINE) actions += `<button class="btn btn-amber btn-sm" data-act="refund" data-id="${o.id}">Klaim refund</button>`;
  }
  if (isBuyer && o.status === 1) {
    actions += `<button class="btn btn-amber btn-sm" data-act="confirm" data-id="${o.id}">Konfirmasi sudah diterima</button>`;
  }
  return `<div class="order-card">
    <h4>Order #${o.id} — ${esc(p ? p.name : "Produk #" + o.productId)}</h4>
    <div>Status: <span class="order-status st-${o.status}">${STATUS_LABEL[o.status]}</span></div>
    <div class="order-meta">Pembeli <span class="mono">${shortAddr(o.buyer)}</span> · ${amount} · dibayar ${fmtDate(o.paidAt)}${o.deliveryRef ? `<br>Referensi pengiriman: <span class="mono">${esc(o.deliveryRef)}</span>` : ""}${extra}</div>
    ${actions ? `<div class="order-actions">${actions}</div>` : ""}
  </div>`;
}
function bindOrderActions(container) {
  container.querySelectorAll("[data-act]").forEach((b) => b.addEventListener("click", () => orderAction(b.dataset.act, Number(b.dataset.id))));
}
async function showOrder(id) {
  const box = $("orderResult");
  box.innerHTML = `<p class="loading">Memuat order #${id}…</p>`;
  try {
    const data = await ethCallRetry(STORE, SEL.getOrder + wordUint(id));
    const o = parseOrder(data);
    box.innerHTML = orderCardHtml(o);
    bindOrderActions(box);
  } catch (e) {
    box.innerHTML = `<p class="loading">Order #${id} tidak ditemukan.</p>`;
  }
}
async function orderAction(act, id) {
  if (!account) { await connect(); if (!account) return; }
  const sel = act === "confirm" ? SEL.confirmReceipt : act === "cancel" ? SEL.cancelOrder : SEL.claimRefund;
  const label = act === "confirm" ? "konfirmasi penerimaan" : act === "cancel" ? "pembatalan" : "klaim refund";
  try {
    toast("Konfirmasi " + label + " di wallet kamu…");
    const txHash = await sendTx({ to: STORE, value: "0x0", data: sel + wordUint(id) });
    const receipt = await waitReceipt(txHash);
    if (receipt.status !== "0x1") throw new Error("Transaksi gagal di chain.");
    toast("Berhasil — order #" + id + " diperbarui.", "ok");
    showOrder(id);
    renderMyOrders();
  } catch (e) {
    toast("Gagal: " + (e.message || e), "err");
  }
}
async function renderMyOrders() {
  const box = $("myOrders");
  if (!account) { box.innerHTML = `<p class="muted">Hubungkan wallet untuk melihat order kamu.</p>`; return; }
  const key = "nuvio-orders-" + account.toLowerCase();
  const ids = JSON.parse(localStorage.getItem(key) || "[]");
  if (!ids.length) { box.innerHTML = `<p class="muted">Belum ada order dari wallet ini di perangkat ini.</p>`; return; }
  box.innerHTML = `<p class="loading">Memuat ${ids.length} order…</p>`;
  let html = "";
  for (const id of ids) {
    try {
      const data = await ethCallRetry(STORE, SEL.getOrder + wordUint(id));
      html += orderCardHtml(parseOrder(data));
    } catch (e) { /* skip orders that fail to load */ }
  }
  box.innerHTML = html || `<p class="muted">Order tidak dapat dimuat.</p>`;
  bindOrderActions(box);
}

/* ---------- boot ---------- */
$("contractLink").href = BSCSCAN + "/address/" + STORE;
$("contractLink").textContent = shortAddr(STORE) + " — BscScan";
$("connectBtn").addEventListener("click", connect);
$("trackBtn").addEventListener("click", () => {
  const v = $("orderIdInput").value;
  if (v === "" || Number(v) < 0) { toast("Masukkan nomor order yang valid.", "err"); return; }
  showOrder(Number(v));
});
$("orderIdInput").addEventListener("keydown", (e) => { if (e.key === "Enter") $("trackBtn").click(); });
document.querySelectorAll("#categoryTabs .tab").forEach((t) => t.addEventListener("click", () => {
  document.querySelectorAll("#categoryTabs .tab").forEach((x) => x.classList.remove("active"));
  t.classList.add("active");
  activeCat = t.dataset.cat;
  renderProducts();
}));
if (window.ethereum) {
  window.ethereum.on("accountsChanged", (accs) => {
    account = accs[0] || null;
    $("connectBtn").textContent = account ? shortAddr(account) : "Hubungkan Wallet";
    if (account) { checkAgentId(); renderMyOrders(); } else { agentIdOk = false; $("agentBadge").classList.add("hidden"); renderProducts(); renderMyOrders(); }
  });
  window.ethereum.on("chainChanged", () => window.location.reload());
}
loadProducts().catch((e) => {
  $("productGrid").innerHTML = `<p class="loading">Gagal memuat katalog dari BNB Chain (${esc(e.message || e)}). Coba muat ulang halaman.</p>`;
});
