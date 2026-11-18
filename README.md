# NUVIO Agent Store

Toko digital-goods on-chain di BNB Chain, khusus pemegang Binance Agent ID.
Dibangun untuk **Binance Agent ID Hackathon** (submit 18 Nov – 9 Des 2026).

Pembeli membayar BNB atau USDT ke kontrak escrow. Dana dikunci sampai pembeli
mengonfirmasi sudah menerima pesanan (akun dikirim via Telegram
[@Nuvio_store_bot](https://t.me/Nuvio_store_bot)). Kalau penjual tidak
mengirim dalam 7 hari, pembeli bisa klaim refund penuh.

## Live

| | |
|---|---|
| Kontrak escrow | [`0x6008c8A96E7b134228000EbdA6F51Fff6a06A786`](https://bscscan.com/address/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786) |
| BscScan (source terverifikasi) | https://bscscan.com/address/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786#code |
| Sourcify | exact_match (creation + runtime), https://sourcify.dev/#/lookup/0x6008c8A96E7b134228000EbdA6F51Fff6a06A786 |
| Website | *(link live menyusul — file statis di `web/`, dipublish sebagai web artifact)* |
| Agent ID contract | [`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`](https://bscscan.com/address/0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) |
| USDT (BSC, 18 decimals) | [`0x55d398326f99059fF775485246999027B3197955`](https://bscscan.com/address/0x55d398326f99059fF775485246999027B3197955) |
| Owner / seller | `0xE2b33DD3F8D982cE7020833E0001f16b4bd706af` (Agent ID: nuvio.ai) |
| Deploy tx | [`0x96297f6ee22d1ce038102ff9f8a34f12e7fde61ef91eef7710f08dd006598225`](https://bscscan.com/tx/0x96297f6ee22d1ce038102ff9f8a34f12e7fde61ef91eef7710f08dd006598225) — blok 134304985, gas 2.403.221 @ 0,0679 gwei = 0,000163 BNB |
| Seed produk tx | [`0xff05357649187684817d2d0d0e3ce559fcf197d2e332211365d510a1382d7177`](https://bscscan.com/tx/0xff05357649187684817d2d0d0e3ce559fcf197d2e332211365d510a1382d7177) — blok 134305526, 8 produk |

## Cara kerja

1. **Beli** — pembeli (wajib memegang Agent ID: `balanceOf > 0` di kontrak
   Agent ID) memanggil `createOrderBNB(productId)` dengan BNB persis harga,
   atau `createOrderUSDT(productId)` setelah approve USDT sejumlah persis
   harga. Dana masuk escrow di kontrak ini.
2. **Kirim** — penjual mengirim akun/layanan via Telegram, lalu memanggil
   `markDelivered(orderId, deliveryRef)` dengan referensi order Telegram.
3. **Konfirmasi / rilis** — pembeli memanggil `confirmReceipt(orderId)` →
   dana cair ke penjual. Kalau pembeli diam, siapa pun bisa memanggil
   `releaseOrder(orderId)` setelah 3 hari sejak pengiriman.
4. **Refund / batal** — pembeli bisa `cancelOrder` kapan saja sebelum
   pengiriman (refund penuh), atau `claimRefund` kalau penjual tidak mengirim
   dalam 7 hari. Pemilik bisa `refundOrder` (goodwill refund) untuk order
   Paid/Delivered.

## Permission owner (didokumentasikan — sesuai aturan hackathon)

Pemilik kontrak (wallet agent `0xE2b33…06af`) BISA:

- `addProduct` / `addProducts` / `updateProduct` / `setProductActive` —
  mengelola katalog dan harga. **Tidak memengaruhi order yang sudah dibayar.**
- `markDelivered` — mencatat pengiriman off-chain (dengan referensi).
- `refundOrder` — refund goodwill untuk order Paid/Delivered.
- `setAgentId` — menunjuk kontrak Agent ID baru **hanya jika Binance
  memigrasikannya**.
- `pause` / `unpause` — menghentikan order baru dalam keadaan darurat.
- `transferOwnership` — transfer kepemilikan standar (Ownable).

Pemilik **TIDAK BISA**:

- menarik dana escrow kecuali lewat alur order yang selesai
  (`confirmReceipt` / `releaseOrder` → ke penjual; `cancelOrder` /
  `claimRefund` / `refundOrder` → kembali ke pembeli);
- mengubah harga order yang sudah dibayar;
- memindahkan dana pembeli ke alamat lain;
- mint token, memungut pajak, membekukan dana, atau menarik approval pengguna.

Tidak ada `selfdestruct`, `delegatecall`, atau transfer BNB langsung
(`receive()` menolak transfer di luar `createOrderBNB`).

## Produk (8, harga awal — bisa diubah owner via `updateProduct`)

| # | Produk | BNB | USDT |
|---|---|---|---|
| 0 | YouTube Premium 1 Bulan | 0,0003 | 0,18 |
| 1 | Spotify Premium 1 Bulan | 0,0002 | 0,12 |
| 2 | Netflix Premium 1 Bulan | 0,0005 | 0,30 |
| 3 | Disney+ 1 Bulan | 0,0004 | 0,25 |
| 4 | Canva Pro 1 Bulan | 0,0002 | 0,12 |
| 5 | Akun Telegram Premium | 0,002 | 1,20 |
| 6 | Followers Instagram 1000 | 0,0005 | 0,30 |
| 7 | Likes Instagram 1000 | 0,0002 | 0,12 |

Harga di atas adalah harga awal mengikuti harga toko Telegram NUVIO
(akun premium murah). Harga final adalah keputusan pemilik toko.

## Keamanan

- OpenZeppelin v5.3.0: `Ownable`, `ReentrancyGuard`, `Pausable`,
  `SafeERC20`. Pola checks-effects-interactions; custom errors.
- **21/21 Foundry test lolos**, termasuk: gating Agent ID, alur BNB &
  USDT lengkap, auto-release setelah window, cancel & claim-refund,
  access control, pause, dan **serangan reentrancy** (attacker contract
  yang mencoba re-enter `confirmReceipt` dari `receive()` — dana hanya
  keluar sekali).
- Deploy memakai optimizer `runs = 1` (ukuran 10.498 byte, gas deploy
  ~3,1 jt di Anvil; aktual 2,4 jt di mainnet).
- Catatan penting: **USDT di BSC memakai 18 decimals** (bukan 6 seperti di
  Ethereum) — diverifikasi on-chain dari 3 RPC. Harga USDT di kontrak dan
  frontend memakai satuan 18 desimal.

## Deploy (bagaimana kontrak ini naik ke mainnet)

`baw contract-call` **tidak mendukung pembuatan kontrak langsung**
(`--to` wajib untuk EVM). Deploy dilakukan lewat factory CREATE2 kanonis
**deterministic deployment proxy**
[`0x4e59b44847b379578588920cA78FbF26c0B4956C`](https://bscscan.com/address/0x4e59b44847b379578588920cA78FbF26c0B4956C)
(EIP-7997, dipakai 25.000+ kali di Ethereum, bytecode terverifikasi sama
di BSC). Calldata = salt `keccak256("NUVIO-AGENT-STORE-V1")` +
init code. Alamat hasil CREATE2 deterministik:
`0x6008c8A96E7b134228000EbdA6F51Fff6a06A786` (sesuai prediksi `cast create2`).
Konstruktor menerima `owner_` eksplisit karena `msg.sender` saat deploy
adalah factory, bukan wallet agent.

Verifikasi source: `forge verify-contract --verifier sourcify`
(tanpa API key) → **exact_match**.

## Frontend (`web/`)

Situs statis tanpa library: `index.html` + `style.css` + `app.js`.
Membaca katalog langsung dari kontrak via RPC publik BSC (3 endpoint
fallback), menulis hanya lewat wallet pengguna sendiri (`window.ethereum`,
Binance Wallet injected). **Tidak ada alur QR code dalam bentuk apa pun.**
Semua aksi aset (bayar, approve USDT jumlah persis, konfirmasi, refund)
meminta konfirmasi pengguna di wallet.

Diuji headless (Chromium): 8 kartu produk ter-render dari data on-chain
asli, harga benar, tanpa error console (selain font Google yang diblokir
di lingkungan tes — fallback font sistem aktif). Desktop + mobile
di-screenshot (`/tmp/nuvio-store-desktop.png`, `/tmp/nuvio-store-mobile.png`).

## Pengembangan

```bash
forge test        # 21 test
forge build       # solc 0.8.29, optimizer runs=1
# Deploy lokal (Anvil): forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

Struktur: `src/NuvioAgentStore.sol`, `test/NuvioAgentStore.t.sol`,
`script/Deploy.s.sol`, `web/` (frontend), `foundry.toml`.
