# NUVIO Agent Store — Jawaban Form Binance Agent ID Hackathon

Status: **proyek LIVE** (kontrak deployed + terverifikasi + 8 produk, website
statis siap publish). Form diisi oleh pemilik (Muhamad) sendiri.
Deadline submit: **9 Des 2026, 08:00 UTC (15:00 WIB)**.

> Tandai: **[FINAL]** = sudah bisa disalin ke form apa adanya.
> **[BUTUH KEPUTUSAN]** = pemilik yang menentukan sebelum submit.

---

## Section I — Basic Project Information

### 1. Project Name — [FINAL]

**NUVIO Agent Store**

### 2. Project Overview (1–3 kalimat) — [FINAL]

NUVIO Agent Store is an on-chain digital-goods store on BNB Chain where only
Binance Agent ID holders can buy premium accounts (YouTube Premium, Spotify,
Netflix, Disney+, Canva), Telegram accounts, and social-media services.
Buyers pay BNB or USDT into a verified escrow smart contract, and funds are
released to the seller only after the buyer confirms delivery — replacing
trust-based Telegram deals with transparent on-chain payment and delivery
protection.

### 3. Project Contract Address(es) — [FINAL]

**NuvioAgentStore (escrow):**
`0x6008c8A96E7b134228000EbdA6F51Fff6a06A786`

- BscScan: https://bscscan.com/address/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786
- Source code: **verified, exact_match on Sourcify** (creation + runtime),
  tampil sebagai verified di BscScan.
- Deploy tx: https://bscscan.com/tx/0x96297f6ee22d1ce038102ff9f8a34f12e7fde61ef91eef7710f08dd006598225
- Kontrak terkait yang dipakai (bukan milik proyek, hanya dibaca):
  - Agent ID: `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
  - USDT (BSC): `0x55d398326f99059fF775485246999027B3197955`

### 4. Project Website / Product Access Link — [FINAL]

**https://muse.ai/s/nuvio-agent-store-xpxt6xe5bxj0kfxh/qpjjKaJbFhcfs8jH59wYfoZx8Pcp_c_glGJGQKP4HvU**

Website live (web artifact, public). Katalog dibaca live dari kontrak, checkout memanggil kontrak asli lewat Binance Wallet, hanya untuk pemegang Agent ID.

### 5. Project Social Media Link (X) — [BUTUH KEPUTUSAN]

**Opsi A (disarankan): buat akun X baru khusus proyek, mis. @NuvioAgentStore.**
Alasan: akun proyek terpisah dari akun pribadi, terlihat lebih serius di
mata juri, dan bisa dipakai untuk Community Promotion Award
(#BinanceWalletHackathon + #AgenticWallet).

**Opsi B: pakai akun yang sudah ada, @newsvrypto.**
Cepat, tapi akun pribadi (konten crypto umum) — kurang rapi sebagai akun
resmi proyek.

Keputusan & link akun: ______________________ (isi setelah diputuskan)

---

## Bagian form lain (draf — sesuaikan dengan pertanyaan persis di form)

Form menunjukkan progress 14% di Section I, jadi ada bagian lain setelahnya.
Draf di bawah ini disiapkan untuk pertanyaan yang umum muncul:

### Agent ID Usage Description — [FINAL]

The project uses Binance Agent ID as **access control and identity**:

- **Access:** only addresses holding at least one Agent ID
  (`balanceOf > 0` on `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) can
  call `createOrderBNB` / `createOrderUSDT`. Non-holders revert with
  `NotAgentIdHolder`. The website checks this live and disables buying
  for wallets without an Agent ID.
- **Identity:** after connecting, the site resolves the connected wallet's
  Agent ID token (via `tokenOfOwnerByIndex` + `tokenURI`) and displays the
  holder's `.ai` name next to the wallet address.
- **Payments:** buyers pay BNB or USDT into the escrow contract; Agent ID
  is the identity that ties each order to its buyer on-chain.

### How It Works / Product Description — [FINAL]

1. Buyer (Agent ID holder) picks a product and pays BNB or USDT to the
   escrow contract.
2. Seller delivers the account/service via Telegram (@Nuvio_store_bot)
   and records delivery on-chain with a reference.
3. Buyer confirms receipt on the website → escrow releases funds to the
   seller. If the buyer stays silent, funds auto-release 3 days after
   delivery.
4. Buyer protection: cancel any time before delivery (full refund), or
   claim a full refund if the seller does not deliver within 7 days.

### Reward Receiving Address — [FINAL]

`0xE2b33DD3F8D982cE7020833E0001f16b4bd706af`
(Agent ID: nuvio.ai — wallet agent / pemilik proyek.)

### Team / Individual — [FINAL]

Individual project by **Muhamad** (NUVIO STORE — toko digital yang sudah
berjalan via Telegram @Nuvio_store_bot). Satu orang, dibantu AI agent
(Chika/Muse) untuk pengembangan kontrak + website.

### Category — [FINAL]

E-commerce / Digital Goods Marketplace (on-chain escrow).

### Open Source — [FINAL]

Smart contract source code is open-source and verified on BscScan via
Sourcify (exact_match). Repository/files: kontrak di
`~/workspace/nuvio-agent-store/src/NuvioAgentStore.sol` (MIT).

### Compliance notes (untuk pertanyaan kepatuhan, bila ada) — [FINAL]

- No QR-code login anywhere; wallet connects only via the injected
  provider (Binance Wallet) and every asset action requires the user's
  own confirmation in their wallet.
- No unlimited approvals: USDT approval is always the exact order amount.
- No promised returns or passive income; the store sells digital goods
  at fixed prices.
- Owner permissions are documented in the README (catalogue, delivery
  marking, goodwill refunds, pause). The owner cannot withdraw escrowed
  funds except through a completed order, cannot change prices of
  paid orders, and cannot move buyer funds to any other address.
- No seed phrases, private keys, API secrets, or pairing codes are ever
  collected.

---

## Yang masih butuh kata pemilik sebelum submit

1. **Link website live** — publish web artifact dari `web/`, tempel link ke Q4.
2. **Akun X proyek** — Opsi A (akun baru @NuvioAgentStore) atau Opsi B
   (@newsvrypto). Kalau Opsi A, buat akunnya dulu, lalu isi Q5.
3. **Harga produk final** — harga saat ini (8 produk, lihat README) adalah
   harga awal mengikuti toko Telegram. Kalau mau diubah, owner bisa
   `updateProduct` kapan saja (gas kecil) — tapi putuskan sebelum submit
   supaya harga di form dan di situs konsisten.
4. **Wallet seller** — saat ini owner kontrak = wallet agent
   (`0xE2b33…06af`), jadi dana hasil penjualan cair ke wallet ini.
   Kalau mau wallet seller terpisah, beri tahu sebelum ada order masuk.
5. **Interaksi Agent ID (≥30 alamat)** — syarat Innovation Award.
   Realistis: butuh promosi — posting X dengan #BinanceWalletHackathon +
   #AgenticWallet (juga ikut Community Promotion Award, 20 pemenang bagi
   $2.000), dan sebar link toko ke komunitas. Tanpa ini, peluang menang
   kecil; proyek tetap berguna sebagai toko NUVIO yang sebenarnya.

---

## Section II — Agent ID Integration Information (diisi user 2026-11-18 ~19:09 WIB)

### 6. Describe how the project uses Agent ID (3–5 kalimat) — [FINAL]

NUVIO Agent Store uses Binance Agent ID as access control and identity. Only addresses holding at least one Agent ID (checked on-chain via balanceOf on the Agent ID contract) can create orders; wallets without an Agent ID cannot buy. After connecting, the website resolves the holder's .ai name from their Agent ID token and displays it next to the wallet address, so every order is tied to a verifiable on-chain identity. Buyers pay BNB or USDT into the escrow contract, and funds are released to the seller only after the buyer confirms delivery. This replaces trust-based Telegram deals with transparent, identity-bound payments and delivery protection.

### 7. Main use cases of Agent ID — [FINAL]

Centang 4 ini:
- Identity Recognition / Identity Verification
- Permission Management / Access Control
- Payment / Settlement
- Agent Identity Binding / Identification

JANGAN centang: Trading / DeFi Interaction, Others.

### 8. Has the product already launched and is it available for users to experience? — [FINAL]

**Yes** — kontrak live di BSC + website live di https://muse.ai/s/nuvio-agent-store-xpxt6xe5bxj0kfxh/qpjjKaJbFhcfs8jH59wYfoZx8Pcp_c_glGJGQKP4HvU

---

## Section III — BNB Chain Contract Information (diisi user 2026-11-18 ~19:11 WIB)

### 9. BNB Chain Contract Addresses — [FINAL]

NuvioAgentStore (escrow, kontrak proyek):
0x6008c8A96E7b134228000EbdA6F51Fff6a06A786

Kontrak terkait (dibaca/dipakai proyek):
- Agent ID: 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
- USDT (BSC): 0x55d398326f99059fF775485246999027B3197955

### 10. BscScan Contract Verification Links — [FINAL]

https://bscscan.com/address/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786#code
(Source code verified — Sourcify exact_match, creation + runtime.)

### 11. Has Agent ID integration been completed and generated on-chain interactions? — [FINAL]

**No** — jujur: integrasi sudah selesai dan live (kontrak deployed + website tersambung), TAPI belum ada interaksi on-chain dari pembeli (belum ada order sama sekali, 0 alamat Agent ID berinteraksi). Konsekuensi: syarat Innovation Award (≥30 alamat) dan ranking Project Awards belum terpenuhi — butuh promosi/pemakaian nyata.

---

## Section IV — Project Showcase Materials (diisi user 2026-11-18 ~19:12 WIB)

### 12. Product Demo Video — [FINAL]

**https://youtube.com/shorts/H4jY00H065o?si=CHC6BuiM6WJA-EyG**

Video demo sudah di-upload user sebagai YouTube Short; judul + deskripsi terverifikasi cocok (2026-11-18 ~19:21 WIB). Tempel link ini ke Q12.

Belum ada video. Video generation TIDAK tersedia untuk akun ini — jalan yang bener: rekam layar HP ~60 detik (tur website + connect wallet + gate Agent ID + alur beli), upload ke YouTube (unlisted), tempel link-nya.
Storyboard 60 detik: (0–10) buka website toko, (10–20) connect Binance Wallet, nama .ai muncul, (20–35) pilih produk YouTube Premium, klik Buy, konfirmasi di wallet, (35–50) order masuk escrow + lacak status, (50–60) BscScan: kontrak terverifikasi + alamatnya.

### 13. Code Repository Link — [BELUM ADA]

Belum ada repo publik. Repo lokal SUDAH siap di ~/workspace/nuvio-agent-store/ (git init, src/ + test/ + script/ + web/ + README) tapi belum ada remote; gh belum login. Yang dibutuhkan: dia bikin repo GitHub kosong (mis. "nuvio-agent-store", public), lalu push — langkah push menyusul setelah repo dibuat.
FALLBACK kalau tidak sempat bikin repo: pakai link BscScan (source terverifikasi di sana): https://bscscan.com/address/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786#code

### 14. Other Supporting Materials — [OPSIONAL]

Bisa isi ini (atau kosongkan):
Website: https://muse.ai/s/nuvio-agent-store-xpxt6xe5bxj0kfxh/qpjjKaJbFhcfs8jH59wYfoZx8Pcp_c_glGJGQKP4HvU
Verified contract source: https://bscscan.com/address/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786#code

---

## Q12 — Metadata upload video demo (dibuat 2026-11-18 ~19:16 WIB)

### Judul YouTube — [FINAL]

NUVIO Agent Store | Buy Digital Goods with Your Agent ID on BNB Chain

### Deskripsi YouTube — [FINAL]

NUVIO Agent Store is an on-chain digital-goods store on BNB Chain where only Binance Agent ID holders can buy premium accounts (YouTube Premium, Spotify, Netflix, Disney+, Canva), Telegram accounts, and social-media services.

In this 60-second demo: connect your Binance Wallet, see your .ai Agent ID, pick a product, and pay BNB or USDT into a verified escrow smart contract. Funds are released to the seller only after you confirm delivery.

Live store: https://muse.ai/s/nuvio-agent-store-xpxt6xe5bxj0kfxh/qpjjKaJbFhcfs8jH59wYfoZx8Pcp_c_glGJGQKP4HvU
Verified contract: https://bscscan.com/address/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786#code
Telegram: @Nuvio_store_bot | @Nuvio_Store_Ai_Bot

Built for the Binance Agent ID Hackathon.
#BinanceWalletHackathon #AgenticWallet #BNBChain #AgentID

### Tags

NUVIO Agent Store, Binance Agent ID, Agentic Wallet, BNB Chain, escrow, digital goods store, Binance Wallet Hackathon, Web3 marketplace

### Teks thumbnail (opsional)

AGENT ID ONLY • ESCROW SECURED
