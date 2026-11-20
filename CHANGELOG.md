## v1.16.9 — UDP stack otomatis semua (UDPGW + UDP-Custom tak lagi opt-in)

### Keputusan pemilik (2026-11-20)
Sebelumnya hanya ZiVPN yang otomatis; UDPGW & UDP-Custom harus diaktifkan lewat
menu (`confirm "Install ...?"`). Kini **semua UDP stack otomatis** saat install utama.

### Changed
- Step install utama (setelah ZiVPN) kini memanggil:
  - `setup/udpgw.sh install` → UDPGW `0.0.0.0:7300` TCP (HTTP Custom)
  - `setup/udp-custom.sh install` → SSH-UDP `1-65535` (listen `:36712`)
- Keduanya pakai `MYTUNNEL_YES=1` (melewati prompt `y/N` saat non-interaktif) dan
  **tahan gagal** (`|| lanjut`) — bila unduhan binary / build cmake gagal, install
  utama tetap selesai.
- Menu tetap punya opsi install/uninstall manual (tidak dihapus) — hanya kini tak
  wajib dipilih lagi.
- Catatan: **Security Group cloud (Tencent) tetap manual** — berlapis di luar VPS,
  firewall/ufw di dalam VPS tak punya kendali atasnya.

### Diverifikasi
- `bash -n` per blok ter-embed: `udpgw.sh`, `udp-custom.sh`, `zivpn.sh` — semua OK.
- `case "${1:-install}"` udpgw menerima subperintah `install` tanpa argumen lain.
- Blok `udpgw.sh` sudah membuka `ufw allow 7300/tcp` + `7300/udp` (fix v1.16.7).

## v1.16.8 — fix UDP-Custom: pasang DNAT 1-65535 (binary tak melakukannya)

### Root cause (HTTP Custom "host:1-65535@user:pass" tak jalan)
- Binary `zhets/udp-custom` v1.4 **TIDAK memasang iptables DNAT** (tidak ada
  string `iptables`/`PREROUTING` di dalam binary), meski komentar installer
  mengira rentang 1-65535 "ditangani binary".
- Akibatnya `DNAT rules: 0` -> UDP ke port 1-65535 tak pernah dialihkan ke
  listen internal `:36712` -> klien SSH UDP / HTTP Custom timeout.

### Fixed
- Unit `udp-custom.service` kini memasang DNAT sendiri via `ExecStartPre`:
  `REDIRECT udp 1:65535 -> 36712` + `ACCEPT udp 36712` (idempoten, `-C || -I/-A`).
- Guard ZiVPN: `ACCEPT udp 5667` dipasang via `-I` (paling atas) sehingga redirect
  1-65535 (di `-A`) tidak menelan rule ZiVPN `5667` & `6000-19999`.
- `ExecStop` membersihkan kedua rule saat stop/uninstall.

### Diverifikasi di VPS live 43.133.36.16
- DNAT `1:65535 -> 36712` aktif; UDP dari luar ke port acak (5555/12345/33333/
  60000/8000) masuk & dialihkan ke 36712 (counter DNAT naik 0->3).
- ZiVPN tetap hidup: `5667` & `6000-19999 -> 5667` tak tertimpa.
- Unit `udp-custom-dnat.service` (oneshot) dipasang manual di VPS live.

## v1.16.7 — fix UDPGW firewall: buka 7300/TCP

### Root cause (HTTP Custom tak bisa konek)
- `badvpn-udpgw` default menerima koneksi **TCP** dari klien (HTTP Custom/KPN Tunnel),
  lalu meneruskan ke UDP. Tapi installer hanya membuka `ufw allow 7300/udp`.
- Akibatnya di VPS baru 43.133.36.16: process `badvpn-udpgw` LISTEN `0.0.0.0:7300` (TCP),
  SYN dari klien sampai (tcpdump membuktikan) tapi ufw DROP tanpa SYN-ACK -> klien timeout.
- Klien memakai format `host:7300@user:pass` = kredensial akun SSH via UDPGW.

### Fixed
- `setup_ufw()` + `install_udpgw()` kini membuka **7300/tcp** DAN 7300/udp.
- Verifikasi pasca-install: `ss -tlnp` (bukan `-ulnp`) supaya listener TCP terlihat.
- UFW 7300/tcp dibuka manual di VPS live 43.133.36.16 -> klien TCP 7300 TERBUKA (terverifikasi dari luar).

## v1.16.6 — fix /etc/timezone tak ikut WIB

### Fixed
- `timedatectl set-timezone Asia/Jakarta` **sukses (exit 0) tapi HANYA menulis
  `/etc/localtime`** — tidak menyentuh `/etc/timezone`. Karena exit-nya 0, fallback
  `|| { ... }` di installer tak pernah jalan, sehingga `/etc/timezone` tetap memakai
  TZ provider (Tencent = `Asia/Shanghai`) padahal jam sistem sudah WIB.
- Dampak: program/util yang membaca file `/etc/timezone` (bukan `localtime`) memakai
  TZ provider -> offset expiry akun/trial bisa meleset.
- Kini ketiganya ditulis **eksplisit & terpisah** (bukan `||`): `timedatectl`,
  `ln -sf zoneinfo -> localtime`, dan `echo "Asia/Jakarta" > /etc/timezone`.

### Ditemukan di VPS baru 43.133.36.16 (Debian 12, Tencent)
- `timedatectl` = Asia/Jakarta (WIB) tapi `cat /etc/timezone` = Asia/Shanghai
- Setelah patch: keduanya `Asia/Jakarta`, konsisten

## v1.16.5 — fix configure-final-443.sh utk VPS baru (stream 443)

### Fixed
- **`NGINX_CONF_DIR: unbound variable`** — variabel dipakai di 3 tempat
  (`xh_h2.inc`) tapi tak pernah didefinisikan; dengan `set -u` ini fatal, membuat
  script berhenti di tengah sehingga langkah "hapus listen 443" terlewati.
  Kini didefinisikan `="/etc/nginx/conf.d"` di header script.
- **Jangkar penyisipan `listen 9443`** — dulu mencari `listen 8443 ssl` (arsitektur
  lama). VPS baru arsitektur **stream 443** TIDAK punya `listen` di blok TLS utama
  (443 datang dari blok stream `ssl_preread`), jadi penyisipan selalu gagal.
  Kini 3 jangkar berurutan: `8443` -> `443`/`[::]:443` -> blok server dgn
  `ssl_certificate` (TLS utama tanpa listen).
- Gejala lama yang ikut teratasi: `bind() to 0.0.0.0:443 failed (98)` — listen 443
  tak terhapus karena script berhenti di bug #1.

### Verified (VPS baru 43.133.36.16, dari config pra-final murni)
- `configure-final-443.sh` menambah 8444 + 9443 dari nol, TANPA error jangkar
- `verify.sh`: **18 PASS, 0 FAIL** (semua listener hidup, ALPN route benar)
- listener: `0.0.0.0:443` (stream) + `127.0.0.1:8444` + `127.0.0.1:9443`

## v1.16.4 — bot silent (tak merespons perintah chat)

### Changed
- Hapus respons semua perintah chat: `/start /help /status /list` + perintah
  manajemen akun + teks acak — **bot kini silent** (tak balas apa pun).
- Reply kosong tak dikirim (guard `[ -z "$reply" ] && return 0`).

### Tetap aktif
- **Notifikasi** otomatis (H-3 expiry, service down) dari `cron/bot_notify.sh`.
- **`/backup`** — kirim file backup terbaru (satu-satunya perintah yang dibalas).
- **Restore** — kirim file backup `.zip/.tar.gz` sebagai document.

## v1.16.3 — revert: bot kembali read-only

### Reverted
- Batalkan semua fitur bot yang baru (v1.16.0-1.16.2) atas permintaan pemilik
  proyek: hapus menu tombol, wizard tanya-jawab, dan kemampuan create/delete/
  renew/trial via bot.
- `bot.sh` kembali **read-only**: `/create_* /delete /renew /trial` ditolak
  ("Fitur dinonaktifkan — buat/hapus lewat menu VPS").
- Perintah tersisa: `/status /list /backup` + restore via file backup.

### Retained (tidak dibatalkan)
- Fix notifikasi H-3 (`23:59:59`) dari v1.15.3 — tetap berlaku.
- Perbaikan timezone WIB (v1.15.2) — tetap berlaku.
- Transport XHTTP + port 443 (v1.15.0-1.15.1) — tetap berlaku.
- `mytunnel-bot.service` tetap jalan (hanya untuk notifikasi/backup/restore).

## v1.16.2 — perbaiki tampilan & error diam bot

### Fixed
- `send_msg` kini pakai `parse_mode=HTML` + fallback plain saat parse gagal
  (sebelumnya tag `<b>/<code>` tampil mentah, pesan terlihat kacau)
- `send_kb`: cek `ok` Telegram; bila gagal kirim plain + log alasan
  (sebelumnya error diam `|| true`)
- `edit_msg`: fallback kirim pesan baru bila edit gagal (teks sama/timeout)
- Keyboard menu **3 -> 2 tombol per baris** (4 baris) biar lega di HP

### Verified (live 43.128.104.92)
- Keyboard menu: 4 baris x 2 tombol (Create|Delete, Renew|Trial, Status|List, Backup|Bantuan)
- Kirim menu via API nyata -> `ok:true`, message_id 1416
- Log bersih, tak ada send_kb error / Bad Request
- `mytunnel-bot` active

## v1.16.1 — bot menu tombol + wizard

### Added
- **Menu tombol Telegram** (`/menu` / `/start`): Create/Delete/Renew/Trial/Status/
  List/Backup/Bantuan (inline keyboard + callback_query).
- **Wizard tanya-jawab**: pilih proto -> username -> durasi (tombol 1/3/7/30/90/
  ketik) -> limit IP. State file `/etc/mytunnel/bot/state_<admin>.txt`, `/cancel`
  membatalkan.
- Helper: `bh_help_text`, `bh_main_menu_kb`, `bh_proto_kb`, `bh_days_kb`,
  `bh_cb_handle`, `bh_wizard_text`, `send_kb`, `answer_cb`, `edit_msg`, `wz_*`.
- **Fallback tetap jalan**: perintah teks `/create_vless user 30 2` tidak berubah.

### Fixed
- `bh_days_kb` printf multi-baris: `%s` di placeholder tak terganti (tombol durasi
  `d:%s` literal). Diubah ke printf 1 baris dgn 5 arg.
- Wizard step dibaca SEBELUM update (keyboard durasi tak muncul) -> baca setelah.
- Precedence `&& ||` di routing create/delete/renew (reply kosong saat error).

### Verified (live 43.128.104.92)
- Create via tombol penuh: VLESS `wzfull` 7h, VMESS `wzbtn` 30h -> 6 link + XHTTP
- Delete, cancel, help, status, list jalan; state file bersih
- `mytunnel-bot` active; akun test dihapus bersih

## v1.16.0 — bot kelola akun (admin)

### Added
- Bot Telegram kini **bisa create/delete/renew/trial** akun (sebelumnya read-only).
  Sebelumnya handler `bh_create_*`/`bh_delete`/`bh_renew`/`bh_trial` sudah ada di
  `handlers.sh` tapi diblokir di `bot.sh` baris 92-95 dgn pesan "dinonaktifkan".
- Unblokir + routing: `/create_ssh|/create_vmess|/create_vless|/create_trojan`,
  `/delete`, `/renew`, `/trial` ke handler sesuai.
- Parse argumen `read -a` (aman dari newline; awk bisa pecah).
- Perbaiki precedence `[ -z ] && ||` di create/delete/renew (sebelumnya reply
  kosong saat error + `$?` bocor ke prompt).
- Tambah unit systemd `mytunnel-bot.service` (enable+restart di live).
- Update teks `/help` utk daftar perintah manajemen akun.

### Verified (live 43.128.104.92)
- `mytunnel-bot` service: active + enabled
- `/create_vless botuji 7` → 6 link (termasuk XHTTP, port 443)
- `/create_ssh botssh 7` → info SSH/Dropbear
- `/delete botuji` → hapus di semua proto
- Setiap create masuk 4 inbound (ws/grpc/hu/**xh**)
- Log bot: `bot cmd /delete from 7637019563` (admin nyata, polling jalan)

## v1.15.3 — fix notifikasi H-3

### Fixed
- Notifikasi **H-3** sebelumnya telat 1 hari (muncul H-2). Penyebab:
  `bot_notify.sh` & `fh_days_left` menghitung `exp_s` dari jam **00:00**,
  padahal `autoexpire` menghapus di akhir hari. `left` jadi floor-1.
- Tambah `23:59:59` pada `exp_s` di **`cron/bot_notify.sh`** (syarat `left=3`)
  dan **`lib/features_helpers.sh:fh_days_left`** (tampilan sisa hari).

### Verified
- `fh_days_left(2026-11-23)` = **3** (sebelum: 2)
- Notif H-3 dummy akun terkirim (state file dibuat); dummy dibersihkan
- `autoexpire*.sh` TIDAK diubah (sudah benar pakai `23:59:59`)

## v1.15.2 — auto WIB saat install

### Added
- Installer kini **otomatis set timezone `Asia/Jakarta`** (WIB) pada step [2/13].
  Sebelumnya TZ mengikuti provider VPS (biasanya UTC/CST), membuat cron
  `autoexpire` (00:00) & expiry akun/trial telat 7-8 jam dari jam Jakarta.
- Fallback `ln -sf /usr/share/zoneinfo/Asia/Jakarta` utk container tanpa
  `timedatectl`; aman di-skip bila keduanya gagal.

## v1.15.1 — judul XHTTP + port TLS 443

### Changed
- Judul link ke-N kini tampil nama transport (mis. **TROJAN XHTTP**), bukan
  fallback `TROJAN LINK 4`. Tambah `_titles+=(... XHTTP)` di vmess/vless/trojan
  (jumlah judul = jumlah link per proto: 6/6/4).
- `ports.conf` `TLS_PORT` **8443 -> 443**: semua link TLS kini memakai port 443
  (443 sudah listen nginx stream + merespons ws/grpc/httpupgrade/xhttp).

### Verified (live 43.128.104.92)
- `bash -n` OK; array 16 judul = 6 vmess + 6 vless + 4 trojan
- link ke-4 trojan -> `TROJAN XHTTP`; vless link xhttp -> port 443

## v1.15.0 — XHTTP transport (vmess/vless/trojan)

### Added
- Transport **XHTTP** kembali (dihapus di v1.3.0 karena 404, kini akar masalahnya
  teridentifikasi): **Xray menuntut path berakhiran `/`**. Config lama memakai
  `/xvless` (tanpa slash) -> `failed to validate path, config:/xvless/` -> selalu 404.
- 3 inbound baru di config Xray: `vmess-xh` (10031), `vless-xh` (10032),
  `trojan-xh` (10033), semuanya `network:"xhttp"` dengan path `/xvmess/`, `/xvless/`,
  `/xtrojan/` (trailing slash).
- nginx: server block **8444** (HTTP/2) kini `include xh_h2.inc` yang berisi
  `location /xvmess/`, `/xvless/`, `/xtrojan/` (prefix match, `proxy_pass` tanpa URI,
  `proxy_request_buffering off`, `chunked_transfer_encoding on`).
- Generator link: +1 link `type=xhttp` per akun (vmess JSON `net:"xhttp"`,
  vless & trojan URI). Helper `_proto_xh_path()`.
- jq add/remove akun kini menyentuh 4 inbound per proto (ws/grpc/hu/xh).

### Why (mengapa dulu 404, sekarang tidak)
Xray normalisasi `path` request dengan trailing slash. Bila config `path` tanpa
slash, validasi gagal sebelum routing. Klien XHTTP juga memakai **HTTP/2** (ALPN
`h2`), yang di stack ini dipetakan `configure-final-443.sh` ke **8444** — bukan 9443.
Server 8444 tidak memuat `locations.inc`, sehingga location XHTTP wajib ditambah
ke sana (file terpisah `xh_h2.inc`).

### Verified (live, 43.128.104.92 / sg2.sunekvpn.cc.cd)
- `xray run -test` -> `Configuration OK` (13 inbound)
- `ss` -> 127.0.0.1:10031/10032/10033 listen
- nginx -t OK; `curl https://sg2.../xvless/` -> HTTP 400 (bukan 404)
- **End-to-end PASS**: klien Xray lokal (socks 19999 -> xhttp-out TLS ke 443)
  `curl --socks5 127.0.0.1:19999 https://api.ipify.org` -> `43.128.104.92`

## v1.14.1 — 2026-11-19 — fallback version basi (auto-sync saat build)

### Gejala pasca rebuild v1.14.0
Menu/status menampilkan `v1.13.34` padahal repo sudah `v1.14.0`.
Hash install.sh di VPS = `7a6d04e1...` (cocok HEAD), jadi bukan installer basi.

### Akar
`install.sh` standalone tidak punya file `VERSION` di sebelahnya saat di-download
(`wget -O install.sh`), jadi `_mt_version` jatuh ke fallback yang HARUS di-hardcode.
Saat bump saya lupa mengubahnya -> tampil versi lama. Pola ini berulang tiap bump.

### Perbaikan permanen
- `install.sh`: placeholder `_mt_version="__BUNDLED_VERSION__"`
- `.githooks/pre-commit`: otomatis injeksikan isi file `VERSION` ke placeholder saat
  commit (via python3, bukan sed — escaping sed di bash ternyata rawan salah).
- Fallback terakhir = `unknown` (bukan versi lama yang menyesatkan).

### Verifikasi
`bash .githooks/pre-commit` menginjeksikan `v1.14.1`; `bash -n install.sh` OK.

## v1.14.0 — 2026-11-19 — SINGLE-FILE: repo jadi 1 installer standalone

### Tujuan
Gabungkan seluruh skrip & konfigurasi repo menjadi HANYA 1 file `install.sh`
yang 100% standalone — dijalankan sendirian tanpa git clone:

```
apt update && apt install -y wget curl && wget -O install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone-patch/main/install.sh && chmod +x install.sh && ./install.sh
```

### Audit (sebelum refactor)
`install.sh` TERNYATA sudah 100% standalone sejak lama:
- Bukti: di-download sendirian ke dir kosong (tanpa git clone, tanpa file lain),
  `chmod +x install.sh && ./install.sh` rc=0, menghasilkan sendiri 18 setup +
  9 menu + 12 fitur + 9 cron + `configure-final-443.sh` + `ports.conf`.
- `bash -n` 80 file .sh hasil ekstraksi & `py_compile` 3 file .py SEMUA OK.
- TIDAK ada fetch file pecahan dari repo saat runtime (3 URL repo di installer
  hanya teks `--help`/panduan, bukan unduhan).

### Yang dikoreksi (agar penghapusan file pecahan TIDAK menyebabkan regresi)
3 blok embed di install.sh ternyata lebih TUA dari file lepas. Disinkronkan
ke versi terbaru (identik, sha256 sama):
- `ports.conf` embed — tambah `ZIVPN_PORT=5667` + `ZIVPN_REDIRECT=6000-19999`
  (KRITIS: mencegah regresi ZiVPN UDP), `TLS_PORT=443,8443`
- `uninstall.sh` embed — tambah blok cleanup login-report + nama service
  `slowdns` / `udp-custom` yang benar (239 baris, sebelumnya 226)
- `configure-final-443.sh` embed — `verify_state()` versi ringkas 2 baris
- `verify.sh` embed sudah IDENTIK sejak awal (tidak diubah)

### File dihapus (semua kini ter-embed penuh di install.sh)
- `configure-final-443.sh`, `ports.conf`, `uninstall.sh`, `verify.sh`,
  `update-login-report.sh`, `xray-guard-install.sh`

### Hasil akhir repo
Hanya 1 installer + metadata GitHub:
`install.sh`, `README.md`, `LICENSE`, `VERSION`, `CHANGELOG.md`, `SHA256SUMS`,
`.gitignore`, `.githooks/`.

### Tidak berubah
Tidak ada fitur, protokol, port, atau logika konfigurasi yang dihilangkan.

## v1.13.34 — 2026-11-19 — bug email acme.sh (cert self-signed)

### Gejala pasca rebuild
Let's Encrypt menolak issue:
```
"contact email has forbidden domain \"example.com\""
urn:ietf:params:acme:error:invalidContact
```
Cert jatuh ke self-signed (issuer CN=domain, O=MyTunnel), bukan LE.

### Akar
Blok pemilihan email acme memakai `get_domain()`. Fungsi itu membaca
`${ETC_BASE}/config/domain.txt`; di skenario tertentu path mengembalikan `-`,
sehingga email jadi `admin@example.com` → LE menolak (domain reserved).

### Perbaikan
- Email diambil EKSPLISIT dari `$ETC/config/domain.txt` (bukan `get_domain()`)
- Validasi regex email + tolak domain reserved (`example|test|invalid|localhost`)
- Bila tak valid: TIDAK register dgn email bogus; acme.sh diinstall tanpa `-m`
  + warning jelas (self-signed sementara, panduan ganti email)
- Bersihkan sisa blok `if false` hasil patch (cari curl/wget dgn kondisi benar)

### Verifikasi
```
domain=sg2.sunekvpn.cc.cd -> admin@sg2.sunekvpn.cc.cd
domain=example.com        -> TOLAK
domain=- / kosong / IP    -> TOLAK
```
Live VPS: register LE sukses, issue webroot sukses, cert `Let's Encrypt` expiry 2027-02-17.

## v1.13.33 — 2026-11-19 — tampilkan proses install penting saja

### Keluhan
v1.13.32 menyembunyikan SEMUA output setup -> proses install nyata (apt unpacking
Dropbear, generate host key, validasi config) ikut hilang. User ingin seperti contoh:
proses nyata tampil, hanya noise yang dibuang.

### Perbaikan
`_mt_step` kini FILTER, bukan menyembunyikan. Tambah `_mt_show()` yang loloskan baris
penting ke terminal:
- `] Setup` / `] Selesai` (header & penutup tiap setup script)
- apt: `Selecting previously`, `Preparing to unpack`, `Unpacking`, `Setting up`,
  `Processing triggers`
- host key: `Generating private`, `Generating .* host`, `SHA256:`
- validasi: `Configuration OK`, `syntax is ok`, `test is successful`, `Active: active`
- `update-initramfs`
Sisanya (banner Xray 2 baris, dump `ss -tlnp`, `conntrack`, `allow NNN`, `skip/sudah`)
tetap dicatat ke LOG tapi tak memenuhi terminal.
Bila step gagal: 15 baris terakhir ditampilkan ke stderr (penyebab tak tersembunyi).

### Hasil dry-run
116 baris terminal; baris penting tampil, noise tersembunyi, LOG tetap penuh.
`bash -n install.sh` OK. Verifikasi filter terpisah: dari 15 baris input, hanya 7
baris penting lolos (apt unpacking, host key, Configuration OK, Selesai).

## v1.13.32 — 2026-11-19 — bersihkan output instalasi

### Keluhan
Saat install, terminal banjir output teknis yang tak perlu.

### Akar
`_mt_step()` streaming SELURUH output setup script (`tee`) ke terminal, termasuk
dump `ss -tlnp`, `sysctl`, `ufw allow` per-port, pesan `[TEST MODE]`, `skip/sudah`,
Xray banner, dsb.

### Perbaikan
- `_mt_step()`: output detail -> LOG saja (`>> "$LOG"`); terminal hanya 1 baris
  ringkasan `✓ [nama] Selesai` (diambil dari baris `] Selesai$` output). STDERR
  tetap lewat ke terminal supaya error tak tersembunyi.
- step Dropbear: samakan dgn `_mt_step` (dulu `| tee` manual, exit via PIPESTATUS)
- step final-443 (`configure-final-443.sh`): output ke log, terminal `✓ final 443 aktif`
- `verify_state()` di `configure-final-443.sh`: dari 9 baris dump (`worker_connections`,
  tiap LISTEN, tiap status service) jadi 2 baris ringkas
- httpmux fallback: output ke log, tanpa `tail -n 5`

### Hasil dry-run
Output terminal install: **210 -> 106 baris**. Terminal kini: preflight, `[N/13] ...`,
1 baris ringkasan per setup, ringkasan akhir + panduan pasca-install.
Detail penuh tetap di `/var/log/mytunnel.log`.

### Koreksi pasca-push
`_mt_step` awalnya menangkap `2>/dev/null` sehingga error setup tersembunyi. Kini
stdout+stderr ditangkap ke var, masuk LOG, dan bila gagal 15 baris terakhir ditampilkan
ke stderr. Verifikasi: setup palsu `exit 3` → rc=3 dipertahankan, pesan error tampil.

## v1.13.31 — 2026-11-19 — LOCK: anti-disconnect tahan rebuild

### Tujuan
"Jangan pernah putus koneksi jika sudah terhubung." v1.13.29/30 memperbaiki live,
tapi belum tahan update paket / rebuild — sysctl saya (90-*) tertimpa 99-*.

### Perbaikan (idempoten)
- Drop-in systemd `dropbear.service.d/keepalive.conf` → `-K 10` selalu dipakai walau
  unit utama ditimpa update paket (systemd merge drop-in terakhir)
- `/etc/sysctl.d/99-zz-keepalive.conf` → `99-zz-*` dibaca paling akhir oleh sysctl.d
  sehingga TAK tertimpa `99-conntrack.conf` / `99-mytunnel-bbr.conf`
- TCP keepalive OS 60s/intvl 10s/probes 6; conntrack established 86400s;
  conntrack_max 262144 (anti "table full, dropping packet")

### Bukti live
```
dropbear-2019 -p 90 -b ... -K 10
tcp_keepalive_time=60 intvl=10 probes=6
nf_conntrack_tcp_timeout_established=86400  nf_conntrack_max=262144
8 layanan active
```
`bash -n install.sh` OK.

## v1.13.30 — 2026-11-19 — SSH reconnect: keepalive agresif

### Lanjutan v1.13.29
`-K 45` masih kurang; klien HC menutup sesi karena tak terima traffic kecil.

### Perbaikan
- Dropbear `-K 45` → `-K 10` (keepalive SSH-level tiap 10s)
- `mytunnel-sshws.py`: TCP keepalive upstream+klien `KEEPIDLE 120→30`, `KEEPINTVL 30→10`,
  `KEEPCNT 8→6`. Loop `for _s in (ssh, conn)` sudah menerapkan ke KEDUA socket, jadi
  hapus blok try/except duplikat yang menyebabkan IndentationError.

### Bukti live
```
dropbear-2019 -p 90 -b ... -K 10
TCP_KEEPIDLE 30 di mytunnel-sshws.py
dropbear log: sesi tahan 50+ detik (sebelumnya 10-15s), banyak sesi tetap terbuka
```
Installer: `bash -n` OK, `.py` blok compile OK.

### Catatan debugging
Dropbear "Early exit: Terminated by signal" 1× di 15:36:41 = restart service saat
patch (systemd `Stopping`), BUKAN crash. Host key DSS di-log `Failed loading` = file
memang tidak ada (hanya rsa+ecdsa), tak berdampak.

## v1.13.29 — 2026-11-19 — SSH sering reconnect

### Gejala
Klien SSH (HC PATCH/GET WS & SSH biasa) putus tiap ~10 detik lalu reconnect sendiri.

### Akar
- Dropbear jalan TANPA `-K` (keepalive 0 = never). Sesi idle dianggap mati oleh
  NAT/telco/tunnel middlebox → TCP direset → klien reconnect.
- nginx blok `@sshws` hanya set `proxy_read_timeout 3600s` tanpa
  `proxy_buffering off`; proxy buffer menahan frame kecil + tak mengosongkan
  koneksi idle → timeout perantara.

### Perbaikan
- Dropbear unit: tambah `-K 45` (keepalive tiap 45s, deteksi mati ~90s)
- nginx semua blok `@sshws`: tambah `proxy_buffering off; proxy_request_buffering off;`
  setelah proxy timeout (idempoten — yang sudah punya tak diubah)
- Dropbear live di-restart dgn `-K 45`; nginx reloaded

### Bukti live
```
ExecStart=/usr/sbin/dropbear -p 90 -b /etc/dropbear/banner -P /run/dropbear.pid -K 45
nginx -t OK; dropbear nginx mytunnel-sshws zivpn xray = active
```
Installer: `-K 45` = 1×, `proxy_buffering off` = 10 blok, `bash -n` OK.

## v1.13.28 — 2026-11-19 — version.txt + hardening NAT ZiVPN

### Temuan pasca rebuild VPS (semua layanan cek)
- 8 layanan aktif (xray, nginx, dropbear 2019.78, mytunnel-sshws/httpmux/tlsmux/stunnel, zivpn)
- SSH WS fix v1.13.27 masuk: `mytunnel-sshws.py` punya RAWMODE, `sshws.sh` wrapper bash
- `mytunnel-slowdns`, `mytunnel-udpgw`, `udp-custom` = unit tak ada (opsional via menu, bukan gagal)

### Bug 1: version.txt = v0.0.0
Installer baca file `VERSION` di sebelah `install.sh`. Install via
`bash -c "$(curl ...)"` tak men-download `VERSION` → fallback `v0.0.0`.
**Fix:** fallback di-hardcode `v1.13.27`→`v1.13.28` (diupdate tiap bump).

### Bug 2: nat PREROUTING `ACCEPT 5667` (baris 1) hilang
Unit `zivpn.service` lama hanya REDIRECT `6000:19999` + INPUT ACCEPT; baris
`ACCEPT 5667` di nat PREROUTING posisi 1 (perlindungan dari DNAT UDP-Custom)
tidak dipasang saat boot. Kini ada di `ExecStartPre`, idempoten.

### Bukti blok installer
```
bash -n install.sh OK
PREROUTING 1 -p udp --dport 5667 -j ACCEPT: True
```

## v1.13.27 — 2026-11-19 — CRITICAL: blok setup/sshws.sh rusak

### Gejala pasca v1.13.26
Rebuild menghasilkan:
```
[11/13] Setup SSH-WS...
/etc/mytunnel/setup/sshws.sh: line 2: import: command not found
/etc/mytunnel/setup/sshws.sh: line 8: syntax error near unexpected token ('
/etc/mytunnel/setup/sshws.sh: line 8: def log(msg):'
✗ Setup SSH-WS gagal
```
Instalasi berhenti; semua layanan `inactive`.

### Akar
Patch sinkronisasi v1.13.26 menimpa BLOK `setup/sshws.sh` (wrapper bash) dengan
ISI Python langsung. Penyebab: saat mencari penutup blok, patch memakai
`__EMBED_EOF__` tetapi blok wrapper mengandung `PY_EOF` di dalamnya — posisi
`find()` salah sehingga blok terganti dari shebang `#!/bin/bash` menjadi
`#!/usr/bin/env python3`. Akibatnya installer menjalankan Python sebagai Bash
(`import: command not found`).

### Perbaikan
- Kembalikan blok `setup/sshws.sh` = wrapper bash (shebang `#!/bin/bash`) dari v1.13.25
- Tanam fix RAWMODE (HC PATCH = raw tunnel, GET WS = framing) ke dalam `PY_EOF` block
- `setup/sshws.sh` tetap wrapper bash; `.py` ditulis ke `mytunnel-sshws.py`
- Unit service `ExecStart=/usr/bin/python3 $PY_BIN` (tidak berubah)
- Validasi: `bash -n install.sh` OK, blok .py compile OK

### Bukti blok installer
```
shebang: #!/bin/bash
RAWMODE: True
ws_encode: True
_method: True
py blok: 5794 byte, compile OK
```

## v1.13.26 — 2026-11-19 — SSH WS: HTTP Custom PATCH mode

### Gejala pasca v1.13.25
User laporkan SSH WS masih "belum bisa" meski dropbear mencatat auth succeeded.
Log sshws: klien datang sebagai `PATCH / HTTP/1.1` (HTTP Custom mode PATCH),
bukan `GET` WebSocket murni.

### Akar
Perbaikan v1.13.25 menambah WS framing (`ws_encode` s2c + `ws_decode` c2s) untuk
semua klien. HC PATCH tidak memakai framing — setelah upgrade ia bicara raw.
Akibatnya banner dropbear dibungkus `` yang HC baca sebagai data SSH invalid →
klien menutup segera setelah auth.

### Perbaikan
- Deteksi method request; `PATCH`/`PUT` = `RAWMODE` (raw tunnel tanpa framing)
- `GET`/`OPTIONS` = tetap WS framing (frame `0x82` s2c, unmask c2s)
- Hapus filter c2s lama yang membuang byte banner; leftover header diteruskan
- Respons tetap `101 Switching Protocols` untuk kedua mode (terbukti bekerja)

### Bukti (VPS hidup)
```
101 sent leftover=0 method=PATCH raw=True
Password auth succeeded for 'eman' from 127.0.0.1:...
```
Login HC PATCH sukses berkali-kali; sesi ditutup normal oleh klien setelah selesai.

## v1.13.25 — 2026-11-19 — Perbaiki ZiVPN & SSH WS timeout

### 1. ZiVPN `connect timeout`
DNAT UDP-Custom (1-65535 → :36712) mencakup port **5667** (bukan range
6000-19999, tapi langsung 5667 dan 5301-7099). Paket klien ZiVPN dibajak ke
udp-custom sebelum mencapai ZiVPN — ZiVPN tidak pernah menerima koneksi.

Fix:
- `ACCEPT 5667/udp` di nat PREROUTING baris 1 (sebelum semua DNAT)
- `REDIRECT 6000-19999 -> 5667` di baris 2
- `EXCLUDE_PORTS` udp-custom ditambah `5667,6000-19999` agar upgrade berikutnya
  tidak mengulang bentrok

Bukti: counter `INPUT dpts:6000:19999` naik dari 0 → 183 paket dalam beberapa
menit; ufw sudah menyimpan `5667/udp` + `6000-19999/udp` di `user.rules`.

### 2. SSH WS timeout
`mytunnel-sshws.py` mengirim banner Dropbear **554 byte raw** ke socket WS
tanpa framing (bukti `strace`), sementara klien WS membaca `SS` (2 byte pertama)
sebagai frame header — sisa `H-2.0-...` jadi payload, `kex_exchange_identification`
gagal: banner line contains invalid characters.

Fix `mytunnel-sshws.py`:
- `ws_encode()`: bungkus payload server→klien dengan frame WS `0x82` (binary, unmasked)
- `ws_decode()`: buka frame mask dari klien sebelum meneruskan ke Dropbear
- header HTTP + leftover byte banner disimpan dan diteruskan utuh
- hapus filter c2s yang membuang byte awal

Bukti: banner kini utuh `SSH-2.0-dropbear_2019.78`; Dropbear mencatat
`Password auth succeeded for 'eman'` lewat port 8080.

## v1.13.24 — 2026-11-19 — ZiVPN tahan reboot: iptables dipasang ulang saat start

### Gejala
Klien ZiVPN `Connection lost: The connect timeout expired` setelah VPS reboot,
padahal `systemctl is-active zivpn` = active dan `ss` menunjukkan `:5667` listen.

### Akar masalah
`setup/zivpn.sh` memasang tiga rule iptables (REDIRECT 6000-19999 -> 5667,
ACCEPT 5667/udp, ACCEPT 6000:19999/udp) **hanya ke memori saat install**.
Bukti di VPS:
```
iptables -t nat -L PREROUTING | grep 6000:19999   -> ada (sebelum reboot)
grep '5667' /etc/iptables/rules.v4                -> kosong / folder tak ada
grep '5667' /etc/ufw/user.rules                   -> 0
dpkg -l iptables-persistent                        -> belum terpasang
```
Setelah reboot semua hilang -> paket UDP 5667 ditolak `Default: deny (incoming)`.
Server tampak sehat, klien tetap timeout.

Catatan: blok `# 5b) ufw: buka UDP ZiVPN` **sudah ada** di skrip tapi VPS ini
di-install dari versi yang belum memuatnya, sehingga port tak pernah masuk
`user.rules`. Tidak ada bug di blok 5b — hanya versi live yang tertinggal.

### Perbaikan
1. **`ExecStartPre` di `zivpn.service`** — memasang ketiga rule iptables secara
   idempoten tiap service start (`-C` dulu, baru `-A`/`-I`). Ini yang membuat
   ZiVPN pulih sendiri setelah reboot tanpa bergantung paket tambahan.
2. `ufw allow 5667/udp` + `6000:19999/udp` dijalankan di VPS hidup
   (blok 5b yang sudah ada, dieksekusi manual karena live tertinggal).

### Hasil uji di VPS (bukan asumsi)
```
flush semua rule  -> NAT=0 IN=0
restart zivpn     -> NAT=1 IN=1 INrange=1   (pulih otomatis)
ufw reload        -> NAT=1 IN5667=1         (tidak terhapus)
restart lagi      -> NAT=1 IN5667=1
probe lokal UDP   -> counter dpt:5667 naik
ssh 22            -> tetap LISTEN, tidak terkunci
zivpn             -> active, NRestarts=0
```
Sebelum perbaikan: 8 klien sempat berhasil connect (rule masih di memori), jadi
masalahnya memang bukan service/config — murni persistensi firewall.

## v1.13.23 — 2026-11-19 — Rapikan bagian SEBELUM menu (banner SSH + dashboard login)

Menu sudah 60 kolom, tapi tampilan sebelum menu masih berantakan.

### 1. Banner SSH pra-login
Dulu isi `banner.txt` cuma satu baris mentah:
```
 | SUNEK VPN - No hacking, use legally |
```
tanpa border, spasi nyasar di awal/akhir, tidak sejajar dengan kotak menu.
Kini kotak 60 kolom yang sama dengan menu:
```
┌──────────────────────────────────────────────────────────┐
│                    SUNEK VPN — SERVER                    │
│                 No hacking, use legally                  │
└──────────────────────────────────────────────────────────┘
```
Berlaku untuk OpenSSH (`Banner /etc/dropbear/banner`) dan Dropbear. Diterapkan
di tiga titik: default wizard, blok `config/banner.txt`, dan `banner_guard`
(tidak menimpa karena isi sumbernya sudah benar).

### 2. Dashboard login (`login.sh`)
Masalah yang ditemukan dari render nyata:
- `draw_box "$brand" 60` -> border 62 karakter (60 dash), 2 lebih dari kotak lain
- seksi traffic (`MONTH/RX/TX/DAY/TRAFFIC`) dicetak **di luar** kotak, mendarat
  setelah `├───` yang tidak pernah ditutup -> kotak terbuka
- baris status `XRAY : ON | SSH-WS : ON | LOADBLC : ON | GOOD` 45 karakter, di luar kotak
- footer `to access use menu command` dan `Up to date` juga di luar kotak

Semua bagian kini di dalam kotak 60 kolom; seksi dipisah `├───┤`, status dan
footer di-center. Ada fallback lokal kalau `lib/helpers.sh` tidak terbaca
(login.sh harus tetap jalan walau lib hilang).

### 3. Fallback warna di login.sh
`RED="${RED:-\033[0;31m}"` — backslash literal, bukan ESC. Diganti ANSI-C
quoting `$'\033[0;31m'` di 9 variabel. `clear || printf '\033c'` -> `clear || true`.

### Hasil ukur dari VPS
```
banner SSH (pra-login)  : 4 baris,  4/4 tepat 60
dashboard login.sh      : 40 baris, 0 masalah (semua di kotak, semua 60)
menu/main + 6 menu      : 0 lebar salah
```

## v1.13.22 — 2026-11-19 — Tampilan menu: satu kotak 60 kolom, judul center

### Akar masalah warna (yang bikin kotak rusak)
`lib/colors.sh` memakai kutip tunggal `RED='\033[0;31m'` -> isinya **backslash
literal**, bukan karakter ESC. Akibatnya:
- seluruh warna di semua menu TIDAK PERNAH aktif
- teks `\033[0;34m` ikut tercetak, jadi lebar baris melar 70-105 karakter
- kotak tidak pernah bisa rata karena border `│` bergeser

Fix: ANSI-C quoting `RED=$'\033[0;31m'` (dan 47 fallback `${RED:-...}` di blok
ter-embed ikut diperbaiki).

### Satu sumber kebenaran lebar
`_box_top/_box_bottom/_box_row/_box_row_menu/_box_center` dipindah ke
`lib/helpers.sh` (dulu hanya di `menu/main.sh`, jadi file `features/*` tak bisa
memakainya). `BOX_W=58` = isi di antara dua `│`; total baris = 60.

### Judul & baris status di tengah
- 65 judul kotak di menu & fitur kini lewat `center_in_box` (dulu `%-56s` = rata kiri)
- 8 label seksi (LOCK & UNLOCK, UTILITIES, ...) ikut center
- baris status `XRAY/SSH/WEB` dihitung paddingnya (`(BOX_W - len)/2`), bukan spasi manual
- 90 baris opsi yang tadinya padding spasi manual -> `printf "%-56s"`

### Hasil ukur (bukan perkiraan)
19 file dirender di VPS, lebar dihitung per karakter (python3, bukan `awk length`
yang salah untuk UTF-8):
```
menu/main 38 baris | ssh 24 | vmess 23 | vless 23 | trojan 23
features 22 | advanced 12 | services 32 | sysinfo 29 | security 24 | ...
TOTAL: 0 baris yang lebarnya salah
```
Sisa 1 selisih 1 char pada baris status = spasi kanan, oleh desain.

## v1.13.21 — 2026-11-19 — Verifikasi limit IP: lock + auto-unlock sesuai durasi

Pertanyaan: apakah limit IP benar-benar berfungsi dan membuka otomatis sesuai durasi
ban? Diverifikasi lewat uji end-to-end (bukan hanya membaca kode).

### Hasil uji nyata — kedua penegak LULUS
**SSH/Dropbear (`cron/limitip.sh`)**
```
uji1 3 IP vs limit=1      -> status=locked, passwd -S=L, lockfile ADA, tercatat di log
uji2 masih dalam durasi   -> status=TETAP locked (tidak dibuka mendahului)
uji3 lewat durasi (3 menit, LOCK_MIN=1)
                          -> status=active, passwd -S=P, lockfile DIHAPUS
uji4 login nyata port 22  -> BERHASIL (akun benar-benar terbuka)
```
**Xray vmess/vless/trojan (`cron/limitip_xray.sh`)**
```
uji1 3 IP vs limit=1      -> status=locked, client dihapus dari config (3->0), lockfile ADA
uji2 masih dalam durasi   -> status=TETAP locked
uji3 lewat durasi + IP sudah normal (1 IP)
                          -> status=active, client dikembalikan (0->3), lockfile DIHAPUS
uji4 lewat durasi tapi IP masih 3 -> ter-lock LAGI (perilaku benar, anti bebas setelah ban)
```

### Mekanisme
- Durasi ban dibaca dari `config/lock_time.conf` (`LOCK_MIN`, diatur menu 3 Lock Time).
- SSH: lockfile `/var/lib/mytunnel/limit/<user>.lock`, mtime sebagai acuan durasi.
- Xray: lockfile `/var/lib/mytunnel/state/limitip_<proto>_<user>.lock`, client dihapus
  dari config saat terkunci dan ditambahkan kembali saat dibuka.
- Grace `limit + 1` IP untuk reconnect NAT; window 180s pada jalur Xray.

### Temuan kecil yang diperbaiki
Baris log auto-unlock SSH memuat durasi hardcoded `after 15m`, sehingga saat
`LOCK_MIN` diubah jadi mis. 5 menit, log tetap menulis 15m (menyesatkan saat
investigasi). Kini membaca `LOCK_MIN` aktual:
```
limitip: auto-unlock <user> after ${LOCK_MIN}m
```
Logika auto-unlock sendiri **benar** — hanya teks lognya yang salah.

### Catatan metodologi
Stub penghitung IP dibuat agar jumlah IP bisa diubah antar uji. Uji pertama pada
jalur Xray sempat tampak gagal karena stub selalu melaporkan 3 IP: begitu dibuka,
run berikutnya langsung menguncinya lagi. Dengan stub dinamis (3 -> 1 IP), jalur
unlock terbukti bekerja normal. Seluruh akun uji dan state dihapus setelah uji;
`jose` kembali `active` dengan 3 transports, `xray -test` OK, service active.

## v1.13.20 — 2026-11-19 — Fix kuota Xray tak pernah terkunci (key mismatch)

### Gejala
Kolom kuota (`$5`) dan limit IP (`$4`) di db akun diisi lewat menu, tapi **kuota
Xray (vmess/vless/trojan) tidak pernah mengunci** akun walau pemakaian sudah
melampaui batas. `used_bytes` ($6) selalu 0 sejak akun dibuat.

### Akar masalah
`cron/quota.sh` membaca stats API Xray yang melaporkan pemakaian per **email**
(`<nama>-<proto>@tunnel`, contoh `jose-vmess@tunnel`), lalu memakai email itu
langsung sebagai kunci ke db. Tapi **kolom 1 db adalah nama polos** (`jose`):
```
key stats API : jose-vmess@tunnel
kolom 1 db    : jose
grep "^jose-vmess@tunnel|" db/vmess.txt  ->  0 baris  (TIDAK cocok)
```
Karena `grep -q "^${email}|"` selalu gagal, seluruh blok (`_add_used`, cek kuota,
kunci) **dilewati** untuk setiap user. Trafik tercatat di stats API tapi tak pernah
sampai ke db, sehingga kuota tak pernah mencapai batas dan akun tak pernah dikunci.

`limitip_xray.sh` tidak terdampak — dia mengiterasi db dan memakai `$user` (nama)
untuk db serta email penuh untuk mencocokkan log. `limitip.sh` (SSH/Dropbear) juga
benar: memakai kolom 1 (`user`) langsung.

### Perbaikan
Normalisasi email -> nama sebelum menyentuh db:
```
key=$(printf '%s' "$email" | sed -E 's/@.*$//; s/-?(vmess|vless|trojan)$//')
```
Lalu `$key` dipakai untuk `_add_used`, lookup `$5/$6/$7`, dan `awk` set status
`locked`. Email penuh tetap dipakai untuk `xray_del_client` karena client di config
memang memakai email.

### Verifikasi live (injeksi stats API terkontrol)
```
kuota 1GB / pemakaian 1.2GB:
  sebelum fix : status=active, used=0, client tetap 3  (TIDAK terkunci)
  sesudah fix : status=locked, used=1288490188, client dihapus (3 -> 0)
                xray -test OK
di bawah kuota (600MB / 1GB): tetap active
```
Akun `jose` dipulihkan (active, 3 transports ws/grpc/hu, `xray -test` OK, service active).

## v1.13.19 — 2026-11-19 — Audit menu SSH/VMESS/VLESS/TROJAN + guard EOF

Audit fungsional seluruh opsi menu protokol (SSH 13, VMESS 12, VLESS 12, TROJAN 12).

### Hasil
| Menu | Opsi | Status |
|---|---|---|
| SSH | Create, Trial, Delete, Renew, Modify Password, Check Login, List, Lock, Unlock, Check Config, Recovery, Edit Limit IP, Edit Limit IP All | 13/13 OK |
| VMESS | semua 12 | 12/12 OK |
| VLESS | semua 12 | 12/12 OK |
| TROJAN | semua 12 | 12/12 OK |

Tidak ada error shell (`command not found` / `syntax error` / `Permission denied`
/ `No such file` / `grep: awk: jq:`). Setiap Create/Delete diverifikasi benar-benar
menulis ke db akun **dan** menambah/menghapus client di `/usr/local/etc/xray/config.json`,
dengan `xray -test` tetap `Configuration OK` setiap langkah. Lock menghapus client dari
config (dibuat kembali oleh Unlock). Renew mengubah kolom exp db + `chage -E` user sistem.
Modify UUID/Password mengganti client di config dan menjaga db & config sinkron.

### Bug yang ditemukan & diperbaiki: loop infinite saat stdin EOF
Loop validasi input di semua protokol tidak punya guard EOF. Saat `read` gagal (stdin
habis), `continue` berulang tanpa henti:

- `do_create` / `do_create_custom` — loop Username: 337 KB output `Username kosong`
- `do_create_custom` TROJAN — loop Password: **1.029.172 baris** sampai timeout

Diperbaiki di 4 menu (semua loop input):
```
read -r user   || { echo dibatalkan; return 2; }   # Username wajib
read -r id     || { echo dibatalkan; return 2; }   # UUID/Password custom wajib
read -r days   || { days=30; break; }              # default 30
read -r quota  || { quota=0; break; }              # default Unlimited
read -r limit_ip || { limit_ip=0; break; }         # default no-limit
```
Wajib (username, UUID, password) membatalkan pembuatan; yang punya default justru
mengambil default dan keluar loop.

### Verifikasi live
```
opsi 2 (Custom) tiap menu saat EOF: 58 baris (sebelumnya 337 KB / 1.029.172 baris)
```
Semua user uji (`uji_vl`, `uji_tr`, `uji_tr2`) dihapus dari db, config xray (12 -> 9
client), dan `/etc/passwd`; `xray -test` OK dan service `active`.

## v1.13.18 — 2026-11-19 — Fix: traffic lama tetap dihitung "user aktif"

### Gejala
User yang **tidak sedang memakai** akun tetap muncul di LOGIN REPORT dan ikut
memicu notifikasi. Contoh: traffic `jose` terakhir jam **01:43**, pukul **02:36**
(jarak 53 menit) user masih tampil pada window 15 menit.

### Akar masalah
`lr_xray_log_rows` (collector.sh) menyaring baris log Xray pada window memakai
`awk match()` dengan regex `^[0-9]{4}\/...`. **POSIX awk tidak mendukung interval
quantifier `{4}`** — pada mawk/gawk bawaan Ubuntu & Debian, `match()` itu **selalu
gagal** (terverifikasi live: `NO-MATCH`).

Karena pencocokan waktu gagal, cabang `if (sec>0 && sec<cut) next` **tidak pernah
dijalankan** → tidak ada satu baris pun yang difilter → seluruh access.log sejak awal
waktu dianggap "dalam window". Semua user yang pernah terhubung muncul sebagai aktif
selamanya.

### Perbaikan
Regex dibuat pakai kelas eksplisit (portabel semua varian awk):
```
[0-9][0-9][0-9][0-9]\/[0-9][0-9]\/[0-9][0-9]   (tanggal)
[0-9][0-9]:[0-9][0-9]:[0-9][0-9]                (jam, tanpa anchor $ agar .123456 lolos)
```

### Verifikasi live (kedua arah)
```
sebelum fix : jose (traffic 01:43) pada 02:36 tampil sebagai aktif  -> SALAH
sesudah fix : jose pada window 15 menit -> jumlah=0, blok VMESS kosong,
              pesan final = 0  -> BENAR
uji positif : sisip 2 baris jose pada detik ini -> "jose | 0GB | 2 IP",
              jumlah IP unik = 2  -> BENAR
```
Baris injeksi uji (IP `10.9.9.x`) dibersihkan dari access.log setelah tiap percobaan.

## v1.13.17 — 2026-11-19 — LOGIN REPORT: hanya protokol aktif + teks mono

### Sebelum
Setiap laporan mengirim **4 pesan** (SSH, VMESS, VLESS, TROJAN) walau hanya satu
protokol yang sedang dipakai user, tiap protokol kosong tampil `(tidak ada user aktif)`.
Setiap blok dibungkus satu `<pre>...</pre>` besar (kotak copy raksasa).

### Sesudah
**1) Hanya protokol yang sedang aktif yang dikirim.**
Blok protokol kini mengembalikan string kosong bila tidak ada user login. `lr_build_messages`
meng-skip blok kosong, jadi user yang hanya login VMESS menerima **1 pesan**, bukan 4.
- `lr_xray_block` — `return 0` (string kosong) bila tidak ada user tercatat pada window log
- `lr_ssh_block` — `return 0` bila `lr_ssh_rows` kosong
- `lr_expired_block` — `return 0` bila tidak ada yang expired

**2) Semua baris mono dan rapi, tanpa `<pre>`.**
Pola yang dipakai di seluruh notif (opsi A): tiap baris jadi satu `<code>...</code>`.
```
<code>IP     : 43.128.104.92</code>
<code>DOMAIN : sg2.sunekvpn.cc.cd</code>
<code>ISP    : ...</code>
<code>Users Login VMESS</code>

<code>jose | 0GB | 1 IP</code>
<code>Total : 1</code>
```
Baris identitas dipisah satu baris kosong dari judul protokol, dan judul dipisah dari
daftar user — jadi tidak menempel jadi satu kotak panjang.

**3) Escaping aman HTML.**
Helper baru `lr_esc` + `lr_code` di `lib/common.sh` meloloskan `&`, `<`, `>` sebelum
dibungkus `<code>`, agar `parse_mode=HTML` tidak gagal bila nama akun memuat karakter itu.
Semua nilai dinamis (nama, IP, domain, ISP, jumlah) lewat helper ini.

**4) Fix tampilan pemakaian.**
Kolom 6 db adalah **byte** (sumber: `proto_create` menulis `0` di kolom `used_bytes`), tetapi
sebelumnya dilabeli `${used_b}GB` sehingga 0 ditulis `0GB` dan 500 jadi `500GB`. Kini lewat
`lr_fmt_gb_short`: `0 → 0GB`, `< 1GB → 512MB`, `≥ 1GB → 1.24GB`.

### Verifikasi live
```
user jose hanya VMESS: pesan final = 1 (sebelumnya 4)
lr_send_report -> "laporan terkirim (1 pesan, chat 7637019563)"
uji sisip log VLESS/TROJAN pada window: hanya protokol ber-user muncul
lr_xray_block VLESS dengan db vless kosong -> string kosong (tak dikirim)
splitter: dipatch per-baris (awk NF) agar tak memotong di tengah <code>
```
SSH collector (`lr_ssh_rows`: hitung sesi sshd parent `[priv]` vs anak, dropbear 1 proses
= 1 sesi) tidak diubah — hanya formatnya yang jadi mono.

## v1.13.16 — 2026-11-19 — Fix "back to menu harus Enter 2x"

### Akar masalah
Setiap sub-menu punya `pause` di **setelah loop** (`done` lalu `pause`). `break`
pada opsi "Kembali" keluar dari `while` lalu tetap menabrak `pause` itu, jadi
user harus tekan Enter sekali untuk keluar sub-menu — lalu induk (`menu/features.sh`)
masih punya `pause` di arm `case`-nya, sehingga total **dua kali Enter**.

### Perbaikan
1. `menu/features.sh` — hapus `pause` dari semua 16 arm `case`. Penanggung jawab
   pause sekarang sub-menu, bukan pemanggil.
2. Sub-menu loop (`security.sh`, `autoupdate.sh`, `backup.sh`, `reboot.sh`,
   `lock_time.sh`, `services.sh`, `banner.sh`, `menu/advanced.sh`) — hapus `pause`
   setelah `done`. "Kembali" kini langsung keluar tanpa Enter.
3. `pause` yang tadinya di top-level file (jalan saat dieksekusi, bukan di dalam
   fungsi) dipindah ke dalam fungsi terkait agar hanya jalan saat memang perlu.
4. `dropbear_version.sh` opsi `list` (dipanggil menu Features opsi 15) kini
   memberi `pause` sendiri karena pemanggilnya tidak lagi pause.
5. `advanced.sh` — sub-menu-nya pause sendiri; `pause` ganda di induk dihapus.
6. Bonus temuan: `reboot.sh`, `backup.sh`, `autoupdate.sh` **hang** saat stdin EOF
   karena `|| c=4` padahal menu hanya 1-3 (opsi 4 tidak ada) → loop "Tidak valid"
   tanpa akhir. Diperbaiki `|| c=3` + label `[1-3]`.

### Verifikasi live
```
EOF (</dev/null): reboot/backup/autoupdate rc=0 (sebelumnya HANG)
"kembali" + satu baris kosong: baris kosong sampai ke menu (Tidak-valid=0)
  reboot, services, security, autoupdate, advanced, lock_time, bandwidth: BENAR
rantai main.sh -> features.sh -> 17 -> 17: Tidak-valid=0, Tekan-Enter=0
```
Pause tetap ada setelah aksi yang menampilkan data (bandwidth info, backup list,
services restart, sysinfo) — itu memang perlu, bukan yang dikeluhkan.

## v1.13.15 — 2026-11-19 — Menu 5: 5 versi Dropbear (2016-2020) sesuai spesifikasi

Daftar versi sekarang: **2016.74, 2017.75, 2018.76, 2019.78, 2020.81** (nomor 1-5).

### Yang diterapkan
1. **Sumber**: `matt.ucc.asn.au/dropbear/releases` utama, `dropbear.nl/mirror/releases`
   cadangan; curl lalu wget. SHA256 wajib cocok dengan `SHA256SUM.asc` resmi.
2. **Compiler GCC 10-14**: dependensi `build-essential zlib1g-dev bzip2 libcrypt-dev`
   dipasang sebelum configure. `SAFE_CFLAGS` sesuai spesifikasi:
   `-O2 -fcommon -w -Wno-error -Wno-implicit-function-declaration -Wno-implicit-int
   -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-unused-result`
   `./configure CFLAGS=... --prefix=/usr --sysconfdir=/etc/dropbear`
   `make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j2`
3. **Host key**: setiap ganti biner, semua `/etc/dropbear/dropbear_*_host_key` dihapus
   dan dibuat ulang (RSA 2048 + ECDSA) memakai `dropbearkey` versi baru — ini yang
   membuat 2016-2019 tidak gagal start karena key ed25519 bawaan distro.
   `apt-mark hold dropbear dropbear-bin` dijalankan.

### Dua bug build yang ditemukan saat uji nyata
- **`make CFLAGS=...` menghapus `-I` Makefile.** Dropbear memakai `CFLAGS+=`, jadi
  argumen command-line *menimpa* seluruh CFLAGS termasuk `-I libtomcrypt/src/headers`.
  Akibatnya 2016.74 gagal: `fatal error: tommath.h: No such file or directory`.
  Fix: CFLAGS diberikan sebagai **variabel lingkungan** (`CFLAGS="$SAFE_CFLAGS" make ...`),
  bukan argumen. Setelah itu 0 error, **0 warning**.
- **`/usr/bin/scp` milik openssh-client.** `--prefix=/usr` + `PROGRAMS="... scp"`
  akan menimpa scp OpenSSH yang dipakai admin. Fix: bila `/usr/bin/scp` dimiliki
  openssh-client, binary scp Dropbear dipasang sebagai
  `/usr/local/bin/scp-dropbear-<tahun>` dan aslinya tidak disentuh.

### Verifikasi live (VPS 43.128.104.92) — semua diuji bergantian
```
1) Dropbear 2016 (v2016.74) checksum cocok -> build -> auth login OK
2) Dropbear 2017 (v2017.75) checksum cocok -> build -> auth login OK
3) Dropbear 2018 (v2018.76) checksum cocok -> build -> auth login OK
4) Dropbear 2019 (v2019.78) checksum cocok -> build -> auth login OK
5) Dropbear 2020 (v2020.81) checksum cocok -> build -> auth login OK
setiap perpindahan: host key dibuat ulang (2 file), service active,
banner sesuai versi (SSH-2.0-dropbear_<ver>)
final 2019.78: service active, paket di-hold, jalur klien
  WS 80/8080/2082/8880 + TLS 443 = SSH-2.0-dropbear_2019.78
```

## v1.13.14 — 2026-11-19 — Checksum Dropbear resmi untuk semua versi, wajib

### Temuan: 2023.88 tidak pernah dirilis
`dropbear-2023.88.tar.bz2` -> HTTP 404 di mirror resmi dan **tidak ada** di
`SHA256SUM.asc`. Versi itu tidak pernah keluar (Dropbear melompat 2022.83 -> 2024.84).
Sudah dihapus dari daftar; pilihan itu dulu hanya menghasilkan unduh gagal.

### Checksum resmi lengkap, bukan cuma 2019.78
Sumber: `https://matt.ucc.asn.au/dropbear/releases/SHA256SUM.asc` (PGP-signed).
12 versi terdaftar di `_sha256_of()`:
`2019.77, 2019.78, 2020.79, 2020.80, 2020.81, 2022.82, 2022.83, 2024.84, 2024.85, 2024.86, 2025.87, 2025.89`

### Checksum sekarang WAJIB
Sebelumnya versi tanpa entri dilewati dengan keterangan. Sekarang **ditolak**:
versi tanpa checksum resmi tidak dipasang sama sekali, dan checksum tidak cocok
menghentikan proses sebelum extract/build.

### Daftar versi menu
`2019.78, 2020.81, 2022.83, 2024.86, 2025.89`

### Verifikasi live (VPS 43.128.104.92) — tiap versi diuji nyata
```
2023.88 : unduh 404 -> ditolak, versi lama tetap aktif
2020.81 : Checksum cocok -> build gcc12 -fcommon -> banner SSH-2.0-dropbear_2020.81
2022.83 : Checksum cocok -> build OK -> banner ..._2022.83
2024.86 : Checksum cocok -> build OK -> banner ..._2024.86
2025.89 : Checksum cocok -> build OK -> banner ..._2025.89
kembali 2019.78 : Checksum cocok -> build OK -> Dropbear v2019.78
final: service active, banner SSH-2.0-dropbear_2019.78
       wrapper exec /usr/local/sbin/dropbear-2019
       binary tersimpan: dropbear-2019/2020/2022/2024/2025
semua jalur klien: WS 80/8080/2082/8880 + TLS 443 = dropbear_2019.78
```

## v1.13.13 — 2026-11-19 — Menu 5: ganti versi Dropbear benar-benar build dari source

### Bug: menu 5 tidak pernah memasang versi yang dipilih
Kode lama hanya menjalankan `apt-get install dropbear` (tanpa versi), sehingga
memilih 2020.81/2022.83/2023.88 tetap memasang paket repo Debian (2019.x) atau
tidak berubah sama sekali. Tidak ada proses unduh/build/verifikasi. Selain itu
`2019.78` tidak ada di `dropbear_versions.txt` walau justru versi itulah yang aktif.

### Perbaikan
- Unduh `dropbear-<ver>.tar.bz2` dari mirror resmi berurutan:
  `matt.ucc.asn.au/dropbear/releases` lalu `dropbear.nl/mirror/releases`
  (curl dulu, wget cadangan, `--timeout=30`).
- Verifikasi SHA256 untuk rilis yang checksum-nya terdaftar (2019.78 =
  `525965971272270995364a0eb01f35180d793182e63dd0b0c3eb0292291644a4`).
  Versi tanpa entri dilewati dengan keterangan eksplisit, bukan diam-diam.
- Build: `CFLAGS="-O2 -fcommon -Wno-error -Wno-unused-result"` — `-fcommon` wajib
  untuk GCC 10+ (gcc 12 di VPS), tanpa itu link gagal.
- Binary per versi dipertahankan (`/usr/local/sbin/dropbear-2019`, `-2020`, ...)
  sehingga bisa bolak-balik; wrapper `/usr/sbin/dropbear` menunjuk versi aktif
  (jalur init.d/systemd Debian). Binary apt lama dibackup `dropbear.apt-<ts>`.
- Dependensi build (`build-essential zlib1g-dev bzip2`) dipasang otomatis.
- Validasi format versi `YYYY.NN`, deteksi "sudah aktif", dan verifikasi akhir:
  service benar-benar melapor versi baru (bukan sekadar "selesai").

### Daftar versi
`2019.78, 2020.81, 2022.83, 2023.88, 2024.86`

### Verifikasi live (VPS 43.128.104.92)
```
build 2020.81 : Checksum dilewati (tak terdaftar) -> Build gcc12 -fcommon -> OK
                service active, banner SSH-2.0-dropbear_2020.81
                wrapper: exec /usr/local/sbin/dropbear-2020
kembali 2019.78: Checksum SHA256 cocok -> Build OK -> Dropbear v2019.78
semua jalur klien setelah tukar versi:
  WS  80/8080/2082/8880 -> SSH-2.0-dropbear_2019.78
  TLS 443               -> SSH-2.0-dropbear_2019.78
login nyata port 90   : banner tampil, auth sukses
```

## v1.13.12 — 2026-11-19 — Audit fungsional 17 opsi menu Features: 4 bug diperbaiki

Bukan sekadar "menu tampil", tapi tiap opsi diuji sampai efek nyata di sistem.

### 1. Opsi 4 (Speed VPS) gagal total
`speedtest --simple` -> `Unrecognized option: --simple`. Flag itu milik
`speedtest-cli` (Python), bukan Ookla `speedtest` 1.2.x yang terpasang.
Fix: deteksi dukungan `--format`, pakai `-f csv`, lalu parse kolom dengan
indeks yang benar (0 server, 2 latency, 5 download bps, 6 upload bps) dan
tampilkan rapi: Server / Ping / Download / Upload.
Catatan: ping di indeks **2**, bukan 4 (4 = packet loss) — sempat salah tampil "0 ms".

### 2. Opsi 13 (Auto Update) melaporkan versi basi
`install.sh` menulis `version.txt` dari blok embed hardcoded `v1.10.5`, sehingga
setiap instalasi baru melapor "Lokal: v1.10.5" walau kode terpasang jauh lebih baru.
Fix: versi diambil berurutan dari `MYTUNNEL_VERSION`, file `VERSION` di sebelah
installer, lalu angka versi pada nama file; fallback `v0.0.0` (bukan angka palsu).

### 3. `lib/banner_guard.sh` tidak pernah dibuat
Installer hanya menjalankan `chmod 644 "$ETC/lib/banner_guard.sh"` tanpa pernah
menulis filenya. Akibatnya opsi "Jadikan banner permanen" & "Pasang cron
banner_guard" selalu menjawab "banner_guard tidak tersedia", dan status banner
di menu Security tampil `n/a`.
Fix: file ditulis lengkap (`bg_status`, `bg_enforce`, `bg_unlock`).
Terverifikasi: banner terkunci `----i---------e-------`, penulisan langsung
ditolak, `bg_unlock` melepas kunci.

### 4. `cron/banner_guard.sh` juga tidak pernah dibuat
Pola bug sama (chmod tanpa tulis), jadi cron `*/5` gagal diam-diam.
Fix: file ditulis dan diuji — rc=0, banner kembali dikunci sesuai config.

### Verifikasi fungsional (VPS 43.128.104.92)
```
 1 Check Bandwidth      4 baris data vnstat (eth0, daily/5min)
 2 Auto Reboot          menu jadwal + reboot sekarang
 3 Lock Time            LOCK_MIN=15 tersimpan & dibaca limitip.sh
 4 Speed VPS            Download 20.8 Mbps, Ping 0.7 ms
 5 Dropbear Version     v2019.78 (3 versi alternatif terdaftar)
 6 Check All Service    21 ON, 0 OFF
 7 Backup               zip 325K, 155 file
 8 Restore              2 backup terdaftar, validasi isi OK
 9 Change Domain        sg2.sunekvpn.cc.cd (DNS check nyata)
10 Banner               40 byte tersinkron ke /etc/dropbear/banner
11 Start/Stop Service   start/stop/restart/status per layanan
12 Security             fail2ban active, ufw active, banner lock/unlock
13 Auto Update          lokal v1.13.11 == repo v1.13.11
14 Info System          Debian 12, Xray/Nginx/Dropbear, disk & RAM
15 Dropbear legacy      /usr/local/sbin/dropbear-2019 ada
16 Advanced             WARP/Routing/SlowDNS/SSH tambahan; slowdns active
17 Back to Menu         kembali ke menu utama
```

## v1.13.11 — 2026-11-19 — Menu rata 60 kolom + 7 menu tak lagi hang saat EOF

### Bug 1: nomor menu tidak rata & border kanan terputus
Dilaporkan lewat screenshot: nomor 1-9 berjarak satu spasi lebih ("` 1.)`"),
10-17 tidak, dan garis `│` kanan tidak sejajar. Penyebab: padding ditulis manual
per baris, sehingga lebarnya bervariasi 52-55 karakter meski kotaknya 60.
Fix: seluruh baris opsi diganti `printf "│ %-56s │\n"` sehingga rata otomatis.
Berlaku di `menu/features.sh` (18 baris), `menu/ssh.sh` (19), `menu/vmess.sh`,
`menu/vless.sh`, `menu/trojan.sh` (18 masing-masing), `menu/advanced.sh` (6).
Baris status WARP/Routing/SlowDNS juga dipersempit 1 karakter (61 -> 60).

### Bug 2: 7 menu berputar tanpa henti saat stdin EOF
Pola `read` tanpa guard di dalam `while true` membuat menu render ulang selamanya
bila stdin tertutup (dipanggil dari skrip, cron, atau pipa non-interaktif).
Terukur `menu/advanced.sh` = 390 baris sebelum timeout.
Fix `read ... || break` pada pembaca menu di: `main.sh`, `features.sh`,
`ssh.sh`, `vmess.sh`, `vless.sh`, `trojan.sh`, `advanced.sh`.
(`features/banner.sh` & `features/lock_time.sh` sudah diperbaiki di v1.13.8.)

### Verifikasi live (VPS 43.128.104.92)
```
menu/ssh.sh      24/25 baris @60  (1 sisa = baris prompt)
menu/vmess.sh    23/24 @60
menu/vless.sh    23/24 @60
menu/trojan.sh   23/24 @60
menu/advanced.sh 12/13 @60
menu/features.sh 22/23 @60
EOF 7 menu     : semua rc=0, tanpa loop
17 opsi fitur  : 16 OK, 0 bermasalah
```

## v1.13.10 — 2026-11-19 — Menu 6 "Check All Service": 21 layanan + ufw benar

### Bug 1: hanya 8 dari 21 layanan diperiksa
`SERVICES="xray nginx sshd dropbear mytunnel-sshws cron vnstat ufw"` — 13 layanan
inti tak pernah tampil maupun bisa dikelola dari menu: tlsmux, stunnel, slowdns,
zivpn, squid, udpgw, ohp-ssh, openvpn tcp/udp/ssl, udp-custom, fail2ban, bot.
Akibatnya layanan mati tidak terdeteksi sama sekali dari menu ini.
Fix: daftar lengkap 21 entri. `restart_dead()` juga ikut memakai `$SERVICES`
(sebelumnya hardcode 4 nama) supaya opsi 1 benar-benar menyalakan apa pun yang OFF.

### Bug 2: ufw dilaporkan OFF padahal aktif
`fh_svc_status` memakai `systemctl is-active`. `ufw.service` bersifat **oneshot**
(exit setelah menerapkan rules), jadi `is-active` = inactive selamanya meski
firewall berjalan. Menu menampilkan "ufw: OFF" pada server yang terproteksi.
Fix: khusus `ufw`, status dibaca dari `ufw status` -> `Status: active`.

### Kerapian tampilan
Baris layanan sebelumnya meluber (nama panjang mendorong `│` kanan keluar kolom).
Sekarang seluruh kotak 60 karakter: nama `%-22s`, status `%-4s`, padding dihitung,
semua border 58 `─` (60 dengan sudut), baris opsi dipad sampai 60.

### Verifikasi live (VPS 43.128.104.92)
```
lebar baris : 32 baris @ 60 karakter, 0 meluber
layanan     : 21 diperiksa, semua ON
ufw         : ON  (sebelumnya OFF)
Akun        : ssh=1 vmess=1 vless=0 trojan=0
```

## v1.13.9 — 2026-11-19 — fail2ban terpasang otomatis saat install

Sebelumnya fail2ban hanya tersedia sebagai tombol manual di `features/security.sh`
dan **tidak pernah terpasang** pada instalasi baru. Sekarang otomatis.

### Perubahan
- `fail2ban` masuk daftar dependensi tahap `[1/13]`.
- `setup_fail2ban()` ditambahkan ke `setup/firewall.sh` dan dipanggil dari `main()`
  (tahap `[6/13]`), jadi ikut jalan pada install non-interaktif `--yes`.
- `features/security.sh` disamakan dengan installer (dua jail + filter yang sama),
  supaya tombol manual tidak menghasilkan konfigurasi berbeda dari hasil install.

### Dua jail, bukan satu
`[mytunnel-sshd]` port **22,444** — OpenSSH admin, filter `sshd`, maxretry 5.
`[mytunnel-dropbear]` port **90** — Dropbear pelanggan, filter `mytunnel-dropbear`
(karangan sendiri), maxretry **8**, bantime 1800.

Alasan filter terpisah: **filter `sshd` bawaan tidak mengenali format log Dropbear.**
Diuji dengan `fail2ban-regex` pada log nyata:
```
filter sshd              -> 2 lines, 0 matched, 2 missed   (port 90 TANPA proteksi)
filter mytunnel-dropbear -> 2 lines, 2 matched, 0 missed
```
Pola yang dikenali: `Bad password attempt for '<u>' from <HOST>:<port>` dan
`Login attempt for nonexistent user from <HOST>:<port>`.

maxretry 8 (bukan 5) karena pelanggan sah sering salah ketik; `127.0.0.0/8` dan
`::1` di `ignoreip` agar pengujian lokal tidak mem-ban diri sendiri.

### Verifikasi live (VPS 43.128.104.92)
```
apt install fail2ban          -> rc=0, Fail2Ban v1.0.2
service                       -> active, enabled
jail list                     -> mytunnel-dropbear, mytunnel-sshd, sshd
fail2ban-regex (log dropbear) -> 2/2 matched
uji ban IP dummy              -> iptables REJECT dibuat, unban bersih
uji 8x bad password (log)     -> Currently banned 1, rule iptables 1
fresh install (hapus jail+filter lalu jalankan ulang) -> keduanya dibuat, aktif
doctor                        -> "fail2ban: ON"
```

## v1.13.8 — 2026-11-19 — Audit menyeluruh fitur: 5 bug nyata diperbaiki

Audit eksekusi nyata (bukan statis) seluruh menu/features/advanced/cron.

### 1. `features/banner.sh` — infinite loop saat stdin EOF
`read -rp " Pilih [1-3]: " c 2>/dev/null || c=3` jatuh ke opsi **3** (aksi),
bukan keluar. Bila stdin tertutup (dipanggil dari script/cron/SSH non-interaktif),
menu berputar tanpa henti: terukur **20.451 baris** output sebelum timeout.
Fix: `|| c=4` (keluar) + label `[1-3]` -> `[1-4]`.

### 2. `features/lock_time.sh` — hang saat stdin EOF
`read -r c` dan `read -r inp` tanpa guard; EOF membuat loop `while true` berputar
selamanya (rc=124). Fix: `read -r c || break`, `read -r inp || continue`.

### 3. `setup/openvpn.sh` — `proto ssl` bikin crash-loop 7078 restart
`_write_server_conf` memakai `$proto` mentah sebagai direktif `proto`. "ssl" dan
"dns" hanya **nama profil**, bukan protokol OpenVPN yang sah, sehingga
`Options error: Bad protocol: 'ssl'` dan unit restart terus-menerus.
Fix: map `ssl -> tcp`, `dns -> udp` sebelum menulis config.
Hasil: `mytunnel-openvpn-ssl` aktif, port 442 listen.

### 4. ZiVPN — akumulasi password hantu
Password akun yang sudah dihapus tidak selalu dicabut (jalur hapus trial/create
gagal tidak melewati `_zivpn_del`). Ditemukan 7 sisa akun trial mati dari 9 entri.
Fix: `_zivpn_reconcile()` di akhir `cron/autoexpire.sh` — satu titik yang membuang
semua password yang user sistemnya sudah tidak ada, idempoten, jaga minimal "zivpn".

### 5. `menu/doctor.sh` — tiga laporan salah
- Cek unit `mytunnel-udp-custom` (nama tak ada) -> selalu "OFF"; unit nyata `udp-custom`.
  Diperbaiki juga di `verify.sh` dan daftar service lain (`slowdns` -> `mytunnel-slowdns`).
- Bandingkan `email == user`, padahal email Xray berformat `<user>-<proto>@tunnel` ->
  akun sehat dilaporkan "HILANG di Xray" sekaligus "orphan". Fix: cocokkan prefix
  `"$user-"` dan buang akhiran `-<proto>@tunnel` saat arah sebaliknya.

### Verifikasi live (VPS 43.128.104.92)
```
18/18 service aktif
banner :90 dropbear_2019.78 | :444 OpenSSH (admin) | :443 dropbear_2019.78
WS     :80/8080/2082/2083/8880 semua dropbear_2019.78 (dari IP publik)
SSH create/delete + zivpn add/del: lulus, sisa 10 -> 9, default "zivpn" tetap
Xray vmess/vless/trojan add/del: lulus, config tetap "Configuration OK"
OpenVPN .ovpn unduh :81 -> HTTP 200, 4 profil + ca.crt
doctor: SSH/vmess konsisten, semua service ON
Fitur EOF: 12/12 keluar bersih (rc=0, tanpa loop)
```

## v1.13.7 — 2026-11-18 — Port 80 tak konek: httpmux jalan kode lama (belum restart)

Setelah v1.13.6 (`SSH_PORT=22` -> `90`), port **80 tetap menampilkan OpenSSH**
sementara 8080/2082/TLS sudah Dropbear. Penyebabnya bukan kode:

- File `/usr/local/bin/mytunnel-httpmux.py` sudah `SSH_PORT=90`, tetapi **prosesnya
  jalan sejak 11:50 sedangkan file diedit 18:50** — Python memuat kode lama ke memori,
  jadi httpmux masih meneruskan ke port 22 (OpenSSH) selama ~7 jam.
- `systemctl restart` pada `mytunnel-httpmux` langsung memperbaiki: banner menjadi
  `SSH-2.0-dropbear_2019.78`.

### Pelajaran operasional
Restart **ketiga** unit mux setiap kali file `.py`-nya diubah:
`mytunnel-httpmux`, `mytunnel-sshws`, `mytunnel-tlsmux`. Restart salah satu saja
TIDAK cukup — masing-masing memegang salinan kode sendiri di memori.

### Verifikasi live (VPS 43.128.104.92, dari luar)
```
port 80   WS upgrade            -> SSH-2.0-dropbear_2019.78
port 80   banner-only (raw SSH) -> SSH-2.0-dropbear_2019.78
port 80   banner + WS (pre-ssh) -> SSH-2.0-dropbear_2019.78
port 8080/2082/8880 WS upgrade  -> SSH-2.0-dropbear_2019.78
tunnel penuh port 80            -> 554 byte, kex lanjut, dropbear 2019
```
Mode raw-SSH langsung (banner dulu tanpa HTTP) hanya didukung di port **80**
(oleh `mytunnel-httpmux`); 8080/2082/8880 lewat nginx `@sshws` yang mengharuskan
WS upgrade lebih dulu — ini perilaku desain, bukan bug.

## v1.13.6 — 2026-11-18 — Semua jalur SSH kini Dropbear 2019.78 (bukan OpenSSH)

Keluhan pemilik: klien (HTTP Custom / HTTP Injector) menampilkan **OpenSSH**,
bukan `dropbear 2019`, walau `dropbear -V` = 2019.78 dan port 90 sudah benar.

**Akar masalah**: seluruh mux SSH meneruskan ke port **22 (OpenSSH)**, bukan
port **90 (Dropbear 2019)**. Dropbear hanya benar bila klien konek langsung ke 90;
semua jalur WS/TLS menyajikan OpenSSH.

Lokasi hardcode `SSH_PORT=22` yang diperbaiki -> `SSH_PORT=90`:
- `usr/local/bin/mytunnel-tlsmux.py` (1443 -> ssh/http)
- `setup/sshws.sh` (mytunnel-sshws.py, 10004)
- `setup/httpmux.sh` (80 -> ssh/nginx)
- `setup/tlsmux.sh` (1443 -> ssh/http)

### Verifikasi live (VPS 43.128.104.92)
Banner yang diterima klien, semua jalur:
```
WS  80/8080/2082/8880 : SSH-2.0-dropbear_2019.78
TLS 4443              : SSH-2.0-dropbear_2019.78
TLS 443 (SNI)         : SSH-2.0-dropbear_2019.78
```
Port 22 tetap OpenSSH (untuk admin/SCP), port 90 Dropbear 2019.
Login password nyata via port 90 berhasil (user uji dibuat lalu dihapus).
Catatan: `mytunnel-tlsmux` WAJIB di-restart, bukan hanya `mytunnel-stunnel`
(stunnel 4443 -> tlsmux 1443, jadi cache lama tetap OpenSSH bila tlsmux tak restart).

## v1.13.5 — 2026-11-18 — Fix OHP: sumber 404 + flag ExecStart salah

`setup/ohp.sh` gagal total di VPS: kedua URL rilis sudah **404** (repo
`lfasmpao/open-http-puncher` & `joawardjan/ohp` hilang), dan kalaupun binary
terpasang, unit systemd memakai flag `-a/-b` yang tidak dikenal binary
(`flag provided but not defined: -a`) -> service restart loop.

### Perbaikan
- Sumber unduh diganti ke rilis yang masih ada dan sudah diverifikasi jalan:
  `darkrenz/open-http-puncher` 0.1 + fallback `Erwingwapo999/Open-http-puncher`
  (asset `ohpserver-linux32.zip`, binary asli `@lfasmpao` v0.1 beta,
  **ELF 32-bit statically linked** — jalan di x86_64 tanpa libc32).
- Tambah penanganan ZIP: deteksi magic `PK`, `unzip` ke temp, ambil `ohpserver`,
  baru install ke `/usr/local/bin/ohp`.
- **ExecStart dikoreksi** ke flag yang didukung binary:
  `-port <port> -proxy <target> -tunnel 127.0.0.1:222x` (sebelumnya `-a/-b`).
- Dua unit dipisah: `mytunnel-ohp-ssh` (9080 -> SSH 444) & `mytunnel-ohp-ovpn`
  (9088 -> OVPN 1194), masing-masing tunnel port berbeda.

### Verifikasi live (VPS 43.128.104.92)
- `bash /etc/mytunnel/setup/ohp.sh install` -> sukses penuh (unduh+unzip+install+enable).
- `mytunnel-ohp-ssh` & `mytunnel-ohp-ovpn` **active/enabled**, listen `:9080`/`:9088`,
  koneksi TCP diterima (log `Added Connection`).
- Lima layanan tambahan terpasang: squid (3128, proxy diuji -> IP keluar benar),
  mytunnel-udpgw (7300), mytunnel-openvpn-tcp (1194/25000, zip :81),
  udp-custom (36712), OHP (9080/9088). SSH 22 tetap terbuka.
- **14/14 service aktif** di VPS.

## v1.13.4 — 2026-11-18 — Audit menyeluruh: fix doctor.sh salah nama unit SlowDNS

Audit penuh 74 blok heredoc di `install.sh` + verifikasi fungsional live di VPS.

### Diperbaiki
- `menu/doctor.sh` memeriksa unit `slowdns` (tidak ada) sehingga SlowDNS selalu
  dilaporkan **OFF** padahal `mytunnel-slowdns` aktif. Nama unit dikoreksi.
- Deploy `setup/zivpn.sh` (blok `ufw allow 5667/udp` + `6000:19999/udp`) ke VPS —
  sebelumnya tertinggal di repo saja.

### Hasil audit (semua lulus)
- Syntax: `bash -n install.sh` OK; **74/74 blok ter-embed** valid
  (4 "FAIL" awal = false positive: `.py`, logrotate, banner, markdown — diverifikasi
  dengan parser masing-masing).
- `shellcheck -S error`: 0 error (hanya `VERSION` kena SC2148, bukan skrip).
- Repo vs VPS: **73/74 file identik** (sisa `config/brand.txt` = data runtime, wajar).
- Helper kritikal ter-load: `ssh_create`, `ssh_delete`, `print_ssh_account_info`,
  `ssh_account_block`, `ah_notify_admin_mono`, `_zivpn_add`, `_zivpn_del`,
  `proto_create`, `print_proto_account_info`, `validate_ssh_username` — semua OK.
- End-to-end: create SSH -> user sistem ada + DB + masuk ZiVPN; delete -> user hilang
  + ZiVPN tercabut + minimal `["zivpn"]` dijaga. VMess create -> 5 link, delete OK.
- `xray run -test` -> Configuration OK. Dropbear v2019.78. Xray 26.11.9.
- TLS 443/4443/8443 -> Let's Encrypt, expiry 2027-02-16.
- Bot @Muesea_bot: getMe OK, service active, notif mono terkirim.
- Cron `autoexpire`/`quota`/`limitip` -> exit 0.

### Catatan (bukan bug)
5 unit (`squid`, `mytunnel-udpgw`, `mytunnel-ohp-ssh`, `mytunnel-udp-custom`,
`mytunnel-openvpn-tcp`) **tidak dipasang installer** — hanya lewat menu advanced
secara manual. Unit file tidak ada, bukan service rusak.

## v1.13.3 — 2026-11-18 — Fix syntax error advanced_helpers.sh: notif tak pernah terkirim

**Akar masalah sebenarnya.** `lib/advanced_helpers.sh` punya baris nyasar `done)`
tepat setelah blok python3 di `ah_notify_admin_mono` (sisa edit format notif
sebelumnya). Bash menolak memuat file karena syntax error di line 139, sehingga
**`ah_notify_admin_mono` TIDAK PERNAH terdefinisi** — dan karena `set -e`/`|| true`
di seluruh pemanggil notif, kegagalan ini **diam** (tidak terlihat di log).

Akibatnya notif Create/Trial (via menu maupun bot) tidak pernah terkirim, meski
token bot valid dan `sendMessage` manual sukses. Patch v1.13.2 (handler bot)
masih diperlukan untuk jalur bot, tapi bukan penyebab utamanya.

### Perbaikan
- Hapus baris `done)` nyasar setelah penutup blok python3 (`')`) pada
  `ah_notify_admin_mono` di embedded `advanced_helpers.sh`.
- `bash -n advanced_helpers.sh` kini OK; fungsi `ah_notify_admin_mono` ter-load.

### Verifikasi live (VPS 43.128.104.92, bot @Muesea_bot)
- `source advanced_helpers.sh` -> `ah_notify_admin_mono` terdefinisi.
- `_bh_notify_block` kirim notif -> OK; `bh_trial ssh` -> user trial dibuat +
  log "notify mono:" tercatat (dua kali: pesan tes & blok trial).
- Akun uji dibersihkan. `mytunnel-bot` active. `bash -n` OK install.sh,
  advanced_helpers.sh, handlers.sh.

## v1.13.2 — 2026-11-18 — Notif Create/Trial kini terkirim saat akun dibuat VIA BOT

Akar masalah: saat akun dibuat melalui **bot Telegram** (`/create_ssh`, `/trial`),
handler `bh_create_ssh` / `bh_create_proto` hanya menampilkan output di terminal dan
**tidak memanggil fungsi notif**. Akibatnya notif mono tidak terkirim ke admin —
padahal jalur **menu** (`menu/ssh.sh`) sudah benar memanggil `ah_notify_admin_mono`.

Kondisi lain sudah benar: token bot & Admin ID valid (getMe ok), `ah_notify_admin_mono`
bekerja (sendMessage `ok:true`).

### Perbaikan (`bot/handlers.sh`)
- Tambah helper `_bh_notify_block` -> kirim blok akun via `ah_notify_admin_mono`
  (diam bila helper tak tersedia).
- `bh_create_ssh`: render output SSH asli **sekali** (`_out`) -> tampilkan ke chat +
  kirim notif dari teks yang sama (tidak render dua kali).
- `bh_create_proto` (vmess/vless/trojan, termasuk `/trial`): sama — render sekali
  via `print_proto_account_info`/`gen_links`, tampilkan + kirim notif.

Trial SSH/proto melewati `bh_create_ssh`/`bh_create_proto`, jadi otomatis ikut.

### Verifikasi live (VPS 43.128.104.92, bot @Muesea_bot)
- `_bh_notify_block` -> rc=0; kirim notif mono HTML -> `ok:true` (msg_id 1322).
- `bash -n` OK install.sh & handlers.sh; `mytunnel-bot` active setelah restart.

## v1.13.1 — 2026-11-18 — Fix email acme.sh ditolak Let's Encrypt

Bug di `setup/cert.sh`: email acme.sh diambil dari `get_domain`, dan bila kosong
di-fallback ke `example.com`. Let's Encrypt **menolak** domain reserved
`example.com` (`urn:ietf:params:acme:error:invalidContact`), sehingga instalasi
non-interaktif tanpa domain selalu gagal issue cert — nyatanya di VPS fresh
43.128.104.92, issue LE gagal 2x sebelum domain di-set.

### Perbaikan
Urutan pemilihan email acme.sh kini:
1. `MYTUNNEL_ACME_EMAIL` (env) — bila di-set.
2. `admin@<domain>` (hasil `get_domain`) — bila domain sudah ada.
3. `example.com` hanya sebagai fallback terakhir + **peringatan eksplisit** ke
   log bahwa LE akan menolak dan cara mengatasinya.

### Verifikasi live (VPS 43.128.104.92)
- akar penyebab dikonfirmasi: `account.conf` lama berisi `admin@example.com`
  -> daftar ulang acme.sh dengan email valid -> issue LE berhasil.
- Setelah cert LE terpasang, semua jalur TLS menyajikan cert domain:
  443 (nginx stream SNI-passthrough -> stunnel 4443), 4443, 8443, 8444, 9443.
- TLS handshake dari luar ke `sg2.sunekvpn.cc.cd:443` -> `Verify return code: 0 (ok)`,
  issuer Let's Encrypt. Layanan nginx/xray/zivpn/dropbear/sshws/stunnel aktif.

## v1.13.0 — 2026-11-18 — Integrasi ZiVPN UDP ke sistem akun SSH

Tambah protokol **ZiVPN UDP** tanpa menu terpisah, terintegrasi langsung ke pembuatan
akun SSH yang sudah ada.

### Instalasi (`setup/zivpn.sh`)
- Unduh binary resmi zahidbd2/udp-zivpn 1.4.9 sesuai arsitektur (amd64/arm64) ->
  `/usr/local/bin/zivpn` (chmod +x).
- Sertifikat self-signed 10 tahun -> `/etc/zivpn/zivpn.{crt,key}`.
- `/etc/zivpn/config.json` (listen `:5667`, auth mode passwords, password default `zivpn`).
- Unit systemd `/etc/systemd/system/zivpn.service` (Restart=always, LimitNOFILE=65535)
  -> `systemctl enable --now zivpn`.
- iptables NAT: redirect UDP `6000-19999` -> `5667` + ACCEPT `5667`/`6000-19999`,
  lalu `netfilter-persistent save`. `-C` dulu sebelum `-A/-I` agar idempotent.

### Integrasi otomatis
- `ssh_helpers.sh` dapat helper `_zivpn_add <user>` & `_zivpn_del <user>` (pakai jq,
  diam bila zivpn/jq tak terpasang, validasi nama user agar tak bisa injeksi JSON,
  `mktemp` + restart service).
- `_zivpn_add` dipanggil di `ssh_create` -> **mencakup SSH manual & Trial SSH** (keduanya
  lewat `ssh_create`).
- `_zivpn_del` dipanggil di `ssh_delete` **dan** di cron `autoexpire.sh` (user kedaluwarsa).
- Hapus selalu jaga minimal `["zivpn"]` agar array auth tak kosong.

### Output
- **Tidak diubah** — 100% format `print_ssh_account_info` asli, tanpa kotak ZiVPN baru.
  User cukup pakai Host + username SSH sebagai password di aplikasi UDP ZiVPN.

### Verifikasi live (VPS 43.128.104.92)
- ZiVPN aktif (listen :5667), NAT redirect UDP 6000-19999 terpasang.
- Uji end-to-end: `ssh_create zivpntest` -> masuk `config.json` (count 1->2);
  `ssh_delete zivpntest` -> tercabut (count 2->1); minimal `zivpn` tetap ada;
  service tetap `active`. `bash -n` OK install.sh, ssh_helpers.sh, zivpn.sh.

## v1.12.0 — 2026-11-18 — SELURUH pesan notif kini mono (garis, judul, label, nilai)

User memilih opsi A: SEMUA teks & symbol dalam notif Create/Trial harus MONO,
tanpa kecuali. Sebelumnya hanya nilai yang mono (label kiri, garis pemisah
`————`, dan judul `SSH/Dropbear`/`OpenVPN`/`VMESS WS TLS` masih plain).

`ah_notify_admin_mono` kini membungkus **setiap baris** (termasuk garis
pemisah, judul blok, dan label) ke `<code>...</code>` — baris kosong tetap
jadi pemisah. Tanpa `<pre>`; semua di-escape `html.escape()`.

Konsisten untuk SSH, VMess, VLESS, Trojan. Grouping tetap via python3
(aman UTF-8; `LC_ALL=C awk` merusak em-dash). Garis pemisah tetap 32 em-dash.

Diverifikasi live di VPS (43.128.104.92, bot @Muesea_bot): render blok SSH
-> 40 baris `<code>` + 3 baris kosong; kirim SSH & VMess ke Telegram sukses;
`mytunnel-bot` active setelah restart; `bash -n` OK install.sh +
advanced_helpers.sh.

## v1.11.10 — 2026-11-18 — Link protokol dicek dulu (utuh), sebelum aturan judul

Bug pada v1.11.9: link `vmess://eyJ2Ij...` diproses oleh cabang label:nilai
SEBELUM dianggap link, sehingga terpotong menjadi label `vmess` + nilai
`//eyJ2Ij...`. Akibatnya tautan protokol utama tampil terpotong dan sulit
disalin utuh.

Urutan pengecekan kini:
1. **Link protokol** (`vmess://`, `vless://`, `trojan://`, `http://`,
   `https://`) dicek PALING AWAL -> dibungkus `<code>` UTUH (tidak terpotong).
2. **Judul blok** = header eksplisit (`SSH/Dropbear`, `OpenVPN`,
   `Account Created Successfully`) tanpa ` : ` -> tetap plain.
3. **label:nilai** (regex `^([^:]{1,30}):(\s*)(.+)$`) -> label plain + nilai
   `<code>` (SSH maupun proto).

Diverifikasi live di VPS (43.128.104.92): render SSH menghasilkan judul plain
(`SSH/Dropbear`) + semua field dalam `<code>`; render VMess memberi link
`vmess://...` utuh dalam `<code>` (tidak terpotong). Kirim SSH & VMess ke
Telegram sukses (bot @Muesea_bot); `mytunnel-bot` active; `bash -n` OK untuk
install.sh dan advanced_helpers.sh.

## v1.11.9 — 2026-11-18 — Pisah label:nilai fleksibel; link protokol jadi <code>

Dua kekurangan pada v1.11.6-1.11.8 (ditemukan saat dicek di Telegram, format
"TES C" yang dipilih user):

1. **Link `vmess://`/`vless://`/`trojan://` di blok proto tidak di-`<code>`.**
   Aturan judul lama hanya mengenali `http://`, sehingga link protokol utama
   (yang paling perlu 1-ketuk copy) jatuh jadi judul plain. Kini semua link
   (`vmess://`, `vless://`, `trojan://`, `http://`, `https://`) dibungkus
   `<code>`.
2. **Proto memakai jarak `:` berbeda** dari SSH (`id : <uuid>`,
   `alterId : 0`, dsb) sehingga deteksi `" : "` lama meleset. Pemisahan
   label:nilai kini memakai regex `^([^:]{1,30}):(\s*)(.+)$` — label kiri tetap
   plain, nilai kanan `<code>`, untuk SSH maupun proto.

Grouping tetap via python3 (aman UTF-8; `LC_ALL=C awk` merusak em-dash).
Judul blok (VMESS WS TLS, SSH/Dropbear, OpenVPN, dsb.) tetap plain.

Diverifikasi live di VPS (43.128.104.92, bot @Muesea_bot): blok VMess ->
6 judul plain + 22 nilai/link dalam `<code>` (semua 5 link protokol kini
`<code>`); kirim SSH & VMess ke Telegram sukses; `mytunnel-bot` active;
`bash -n` OK install.sh + advanced_helpers.sh.

## v1.11.8 — 2026-11-18 — Kembalikan garis pemisah ke 32 em-dash (SSH & proto)

Garasi pemisah `DASH` di `lib/ssh_helpers.sh` dan `lib/proto_helpers.sh` sempat
tergeser ke 44 em-dash saat patch judul/field sebelumnya (tertimpa oleh edit
bertumpuk). Keduanya kini disamakan kembali ke **32 em-dash** (pendek, pas di
Telegram) — konsisten untuk SSH maupun VMess/VLESS/Trojan.

Terverifikasi live di VPS (43.128.104.92): `local DASH=` di kedua lib = 32
em-dash; render blok SSH menampilkan garis 32 em-dash di atas/bawah judul
`SSH/Dropbear`. `bash -n` OK; `mytunnel-bot` active setelah restart.

## v1.11.7 — 2026-11-18 — Perbaiki judul vs field & nilai ter-strip di blok mono

Dua kekurangan pada implementasi v1.11.6 (ditemukan saat dicek di Telegram):

1. **Baris ber-indentasi yang punya ` : ` salah masuk judul.** `Expired` awalnya
   dianggap judul (karena barisnya ter-indentasi) sehingga nilainya TIDAK
   di-`<code>`. Kini judul ditentukan dari daftar header eksplisit
   (`SSH/Dropbear`, `OpenVPN`, `Account Created Successfully`) + syarat tanpa
   ` : `; baris `    Expired : 2026-11-20` kembali diproses sebagai field dan
   nilainya dibungkus `<code>`.
2. **Nilai kini di-`.strip()`** sebelum di-`<code>` — menghilangkan spasi
   terdepan yang ikut terbawa (mis. `Expired -> " 2026-11-20"`).
3. **Komentar judul duplikat dibersihkan** (sisa 3 patch bertumpuk).

Hasil klasifikasi blok SSH (diverifikasi live di VPS 43.128.104.92):
`SSH/Dropbear` & `OpenVPN` = TITLE (plain), `Expired` = FIELD (`<code>`),
link zip = VALUE (`<code>`), login cepat & identitas & payload = FIELD
(`<code>`), label kiri tetap plain. `bash -n` OK, kirim ke Telegram sukses,
`mytunnel-bot` active setelah restart.

## v1.11.6 — 2026-11-18 — ATURAN FORMAT notif: hanya nilai di-<code>, label plain

Menerapkan aturan format eksplisit untuk `ah_notify_admin_mono` (parse_mode=HTML):

- **HANYA nilai yang perlu disalin** dibungkus `<code>` — baris SSH
  WS/SSL/UDP/SLOWDNS (`host:port@user:pass`), HOST, NameServer, Username,
  Password, PUB Key, Payload WS, Payload ENHANCED, link OpenVPN.
- **Label di kiri** (SSH WS, HOST, Username, TLS, ...) **tetap teks biasa**,
  tidak dibungkus tag.
- **Judul blok tetap plain**: `SSH/Dropbear`, `OpenVPN`,
  `Account Created Successfully` (dideteksi dari indentasi besar / daftar
  header) — tidak di-`<code>` karena bukan nilai copyable.
- **Tanpa `<pre>`** untuk seluruh pesan.
- **Semua nilai dinamis di-escape** `html.escape()` supaya karakter `<`, `>`,
  `&` pada password/payload tidak merusak pesan (mis. password `pa&ss<word>`
  dikirim sebagai `pa&amp;ss&lt;word&gt;`).
- Helper `code(t)` dibuat agar pembungkusan tidak berulang.

Pemisahan label-nilai hanya pada pemisah ` : ` pertama, dengan syarat label
tidak memuat `[`/`]` (agar payload `[crlf]`/`[host]` tidak salah dipotong).

Diverifikasi live di VPS (43.128.104.92, bot @Muesea_bot): render SSH → label
plain + nilai `<code>`, judul plain, escape teruji; kirim nyata sukses;
`mytunnel-bot` active; `bash -n` OK install.sh + advanced_helpers.sh.

## v1.11.5 — 2026-11-18 — Blok akun Telegram dikelompokkan PER BAGIAN (copy 1-ketuk per bagian)

Setelah dicek di Telegram: per-baris `<code>` tidak memberi copy 1-ketuk untuk
baris panjang (mis. `sg2.sunekvpn.cc.cd:80@user:pass`), dan satu `<pre>`
(v1.11.3) jadi satu kotak raksasa. Kompromi yang benar: kelompokkan PER BAGIAN.

`ah_notify_admin_mono` kini memecah blok akun menjadi bagian-bagian (blok
login cepat, identitas, daftar port, payload WS, payload enhanced, link
OpenVPN, expired — dipisahkan garis pemisah / baris kosong). Tiap bagian
menjadi SATU `<code>...</code>`: tetap MONO, kolom sejajar, dan tiap bagian
punya tombol copy sendiri (login cepat & payload bisa disalin 1-ketuk).

Grouping memakai `python3` (bukan awk): `LC_ALL=C awk` memotong byte UTF-8 dan
merusak em-dash sehingga garis pemisah tak terdeteksi. Python menganggap baris
pemisah = baris kosong ATAU baris yang seluruh karakternya identik (em-dash,
`-`, `=`, dsb).

Diverifikasi live di VPS (43.128.104.92): render blok SSH menghasilkan 9 blok
per bagian, tiap blok `<code>` tertutup rapi; kirim ke Telegram sukses
(bot @Muesea_bot); `mytunnel-bot` active setelah restart; `bash -n` OK untuk
install.sh dan advanced_helpers.sh.

## v1.11.4 — 2026-11-18 — Kembalikan blok mono per baris (batal satu <pre>)

v1.11.3 menggabungkan seluruh pesan ke satu `<pre>` (satu kotak copy raksasa).
Setelah dicek di Telegram ternyata bukan yang diinginkan. Kembali ke pendekatan
`<code>` per baris: setiap baris tetap MONO dan kolom sejajar, tanpa dipaksa
menjadi satu kotak kode tunggal.

`ah_notify_admin_mono` kembali membungkus tiap baris ke `<code>...</code>`
(dengan escape `&`/`<`/`>`), parse_mode=HTML, fallback teks polos bila HTML gagal.

Diverifikasi live di VPS (43.128.104.92): `bash -n advanced_helpers.sh` OK,
`mytunnel-bot` active setelah restart, kirim blok akun SSH sukses.

## v1.11.3 — 2026-11-18 — Blok akun jadi SATU <pre> -> tombol copy 1-ketuk di Telegram

Sebelumnya `ah_notify_admin_mono` membungkus SETIAP baris jadi `<code>...</code>`
terpisah (40 blok kecil). Telegram hanya menampilkan tombol "copy" bila
seluruh pesan adalah SATU blok `<pre>` — dengan `<code>` per-baris, tiap baris
hanya potongan mono kecil dan tidak ada copy 1-ketuk untuk baris panjang
(mis. `sg2.sunekvpn.cc.cd:80@user:pass`).

`ah_notify_admin_mono` kini membungkus seluruh pesan ke SATU
`<pre>...</pre>` (HTML, escape `&`/`<`/`>`). Hasil: satu kotak kode dengan
tombol copy 1-ketuk untuk seluruh blok akun (SSH, VMess/VLESS/Trojan), kolom
tetap sejajar karena mono. Link `vless://`/`vmess://`/`trojan://` ikut ke
dalam kotak yang sama — tetap bisa disalin.

Diverifikasi live di VPS (43.128.104.92, bot @Muesea_bot): kirim blok SSH
sebenarnya lewat `<pre>` -> API jawab `ok:true` (message_id 1272). Fallback
tetap ada: bila HTML gagal, kirim teks polos.

## v1.11.2 — 2026-11-18 — Format blok akun SSH baru (mirip panel tunneling populer)

`ssh_account_block()` ditulis ulang. Format baru, mono, terstruktur per bagian:

- **Judul `SSH/Dropbear`** di tengah (mengganti "Account Created Successfully").
- **Blok login cepat** di atas: `SSH WS / SSH SSL / SSH UDP / SSH SLOWDNS`
  dalam format `host:port@user:pass` (siap dipakai langsung di aplikasi klien).
- **Identitas akun**: HOST / NameServer / Username / Password / PUB Key.
- **Daftar port lengkap** (label diperlebar ke 18 kolom agar sejajar): TLS,
  None TLS, Any, OpenSSH, Dropbear, SlowDNS, UDP-Custom, OHP+SSH, Squid,
  BadVPN UDPGW, OpenVPN TCP/SSL/UDP/DNS, OHP+OVPN.
- **Payload WS** dan **Payload ENHANCED** (templat `[host]`/`[ua]`/`[crlf]`
  untuk aplikasi HTTP-injector).
- **Judul `OpenVPN`** + link `myvpn-config.zip`.
- **Expired** dipindah ke paling bawah.

PUB Key (dulu "SlowDNS Pubkey") & NameServer (dulu "SlowDNS NS") kini di
bagian identitas; `SlowDNS Type` dihapus dari tampilan (masih ada di config).

Diverifikasi live di VPS (43.128.104.92, akun `okem`): render sesuai desain,
40/40 baris mono berakhir `</code>`, total pesan 2184 char (< batas Telegram
4096). `bash -n` OK untuk install.sh dan ssh_helpers.sh.

## v1.11.1 — 2026-11-18 — Notif Create/Trial VMess/VLESS/Trojan kini MONO di Telegram

SSH sudah lama terkirim mono (via `ah_notify_admin_mono`, HTML `<code>` per
baris -> kolom sejajar). VMess/VLESS/Trojan masih memakai
`ah_notify_admin` (parse_mode=Markdown) yang HANYA membuat link `vless://`
mono; sisa blok (Remarks/CITY/ISP/Port/Domain) tampil sebagai teks biasa,
kolom tak sejajar, dan em-dash berisiko mengganggu parser Markdown.

Diganti: seluruh pemanggilan notif yang mengirim blok akun proto
(create / trial / detail / recovery — di `menu/vmess.sh`, `vless.sh`,
`trojan.sh`) kini memakai `ah_notify_admin_mono` agar tampil mono dan kolom
sejajar, konsisten dengan SSH. Notif 1-baris (delete/backup/expired) tetap
`ah_notify_admin` Markdown biasa (tak perlu mono).

`ah_notify_admin_mono` kini juga membungkus baris link `vless://`/`vmess://`/
`trojan://` ke `<code>` masing-masing, sehingga tap-untuk-copy pada link
tetap berfungsi (sebelumnya hanya `ah_notify_admin` yang melakukannya).

Diverifikasi live di VPS (43.128.104.92): render `print_proto_account_info
vmess` + pipeline HTML -> 41/41 baris berakhir `</code>` (mono tertutup
rapi, kolom sejajar). `bash -n` OK untuk install.sh, advanced_helpers.sh,
dan ketiga menu proto.

## v1.11.0 — 2026-11-18 — Garis pemisah output akun: `-` -> em-dash `—`

Output Create/Trial (SSH via `print_ssh_account_info` di `lib/ssh_helpers.sh`,
VMess/VLESS/Trojan via `print_proto_account_info` di `lib/proto_helpers.sh`)
memakai garis pemisah `DASH` dari 36 hyphen ASCII (`-`). Diganti ke em-dash
`—` agar tampil rapi di Telegram (kirim notif create/trial) tanpa tampak
seperti daftar strip pendek.

Hanya variabel `DASH` (garis dekoratif) yang diubah — tidak menyentuh hyphen
di UUID, path ws/gRPC (`/vmess`, `/trojan`), angka port, atau argumen baris
perintah, sehingga link/config akun tetap valid.

Diverifikasi live di VPS (43.128.104.92): `print_ssh_account_info` kini
menampilkan garis em-dash penuh di antara field akun.

## v1.10.9 — 2026-11-18 — OpenVPN: ganti opsi yang dihapus di OpenVPN 2.5+

`setup/openvpn.sh` menulis `client-cert-not-required` ke config server. Opsi itu
Dihapus di OpenVPN 2.5+ (diganti `verify-client-cert none`), sehingga di VPS
dengan OpenVPN baru (terverifikasi Debian 12 / OpenVPN 2.6.14) semua service
OpenVPN gagal start:

    REMOVED OPTION: --client-cert-not-required, use
    '--verify-client-cert none' instead
    Exiting due to fatal error
    systemd: mytunnel-openvpn-tcp.service: Failed with result 'exit-code'

dan service masuk loop restart. Diganti `verify-client-cert none` — valid di
OpenVPN 2.5/2.6 dan maknanya identik (autentikasi PAM username/password,
client cert tidak wajib, tetap ada `plugin .../login` + `crl-verify`).

Diverifikasi live di VPS produksi (43.128.104.92, Debian 12 / OpenVPN 2.6.14):
config dipatch, `systemctl enable --now mytunnel-openvpn-tcp mytunnel-openvpn-udp`
→ kedua service `active` dan log `Initialization Sequence Completed`.

## v1.10.8 — 2026-11-18 — KOREKSI v1.10.6: _mt_step di script ter-embed (install mati di [8/13])

v1.10.6 mengganti 6 tempat `| tee` menjadi `_mt_step`, tetapi 5 di antaranya
jatuh DI DALAM script yang ditulis installer lewat heredoc (`setup/xray.sh`,
`setup/cert.sh`, `setup/nginx.sh`, `setup/openssh.sh`, `setup/squid.sh`).
Script ter-embed itu BERDIRI SENDIRI saat dijalankan `bash` dan tidak mewarisi
fungsi `_mt_step` milik `install.sh`, sehingga di VPS nyata:

    /etc/mytunnel/setup/xray.sh: line 228: _mt_step: command not found
    Validasi Xray gagal
    ✗ Setup Xray gagal  →  installer berhenti di [8/13]

Bukan config Xray yang rusak — validasi yang mati karena helper tidak
terdefinisi. (Bukti di VPS produksi: `xray-guard` setelahnya berhasil
restart xray dan aktif kembali, artinya config.json valid dan binary jalan.)

Perbaikan: setiap script ter-embed kini memiliki definisi `_mt_step` lokal
sendiri (identik semantiknya dengan versi installer: ambil status asli dari
`PIPESTATUS[0]`, tanpa `||` yang me-reset PIPESTATUS).

Verifikasi: 5/5 script ter-embed punya definisi helper; `bash -n` bersih
untuk install.sh dan tiap script yang diekstrak; shellcheck 0 error/warning;
uji fungsional exit 23 terdeteksi & exit 0 tetap lolos.

## v1.10.7 — 2026-11-17 — CFLAGS build Dropbear disamakan dengan installer proven (anti -Werror)

`install_dropbear()` membangun Dropbear 2019.78 dengan `CFLAGS="-O2 ${db_cflags}"`
saja (`-fcommon` otomatis bila GCC >= 10). Dua flag yang membuat build yang
sudah terbukti nyala di VPS produksi tetap bertahan hilang:

- `-Wno-error` — GCC baru (11/12) mempromosikan sejumlah warning Dropbear 2019
  menjadi error, build gagal walau kode valid.
- `-Wno-unused-result` — `write()`/`read()` di Dropbear 2019 memicu warning
  `_FORTIFY_SOURCE` yang ikut jadi error bila `-Werror` aktif.

Keduanya ditambahkan ke `./configure` agar build Dropbear sama tangguhnya
dengan installer proven (`install-full-vpn.sh` di tunnel-bot). `-fcommon`
tetap ditambahkan otomatis pada GCC >= 10 (GCC 11 default `-fno-common`
menghasilkan binary rusak). `dropbearconvert`/`scp` tidak ditambahkan ke
`PROGRAMS` karena repo ini tidak memakai keduanya (sudah diverifikasi:
tanpa referensi `scp`/`dropbearconvert` di seluruh `install.sh`).

Verifikasi: `bash -n` bersih, satu-satunya `./configure` build Dropbear,
syntax OK, SHA256SUMS diregenerasi.

## v1.10.6 — 2026-11-17 — Enam titik `| tee` yang membungkam exit code + chmod cert salah variabel

`perintah | tee` selalu mengembalikan status `tee` (0). Semua pengecekan
`if ! perintah | tee` / `perintah | tee || { ... }` di file ini karenanya
tidak pernah bisa gagal — perintah yang gagal dianggap sukses. Helper
`_mt_step()` (status diambil dari `PIPESTATUS[0]`) sudah ada sejak lama;
enam tempat yang belum memakainya kini dipindah ke situ:

- `issue_cert()`: issue EC/RSA (kegagalan LE 429 / DNS belum propagasi
  sekarang benar-benar memicu fallback self-signed, 443 tidak mati senyap)
  dan `--install-cert` ke staging.
- `validate_config()` Xray (`run -test`) — konfigurasi rusak kini
  tertangkap sebelum xray di-restart.
- `validate_config()` nginx (`nginx -t`), `validate_sshd()` (`sshd -t`),
  validasi squid (`squid -k parse`): validasi config sebelum restart service.

Diperbaiki pula `chmod 600 "$CERT_KEY" / chmod 644 "$CERT_CRT"` di
`issue_cert()` — variabel scope itu `$cert_key`/`$cert_crt` (lowercase),
jadi `chmod` sebelumnya dieksekusi pada string kosong (diam-diam gagal)
dan permission file sertifikat tidak pernah diset.

Catatan: `| tee || true` pun me-reset `PIPESTATUS` (perintah `true`/assignment
setelah `||` menjadi terakhir dalam pipeline), jadi pola "tambahkan
`|| _rc=$PIPESTATUS`" TIDAK cukup — `_mt_step` tanpa `||` dipakai.

Terverifikasi dengan uji shell terhadap ketiga pola (exit 23 terdeteksi,
exit 0 tetap lolos), `bash -n` bersih, shellcheck 0 error/warning.

## v1.10.5 — 2026-11-12 — Akun tunneling bisa dipakai setelah auth: useradd -m, bukan -M

`ssh_helpers.sh` membuat akun dengan `useradd -M` (tanpa home). Dropbear 2019
`chdir` ke home user setelah auth; home tidak ada → "Error changing directory"
→ koneksi langsung ditutup walau password benar (log: `Password auth succeeded`
lalu `Exit: Error changing directory`). Ganti ke `useradd -m`: home dibuat,
akun tetap `-s /bin/false` sehingga tidak bisa shell login, tapi dynamic/socks
forward (yang dipakai klien tunnel) tetap hidup. Diverifikasi live: SOCKS5
handshake `0500` dan HTTP 204 lewat `-D` pada port 90.
## v1.10.4 — 2026-11-12 — Install baru tidak menggantung; Dropbear 2019 benar-benar terpasang

### BUG KRITIS: installer diam berjam-jam di VPS baru ("get release list success" / "Installing Xray")
Bukan Xray yang hang. Tiga sebab nyata, semuanya di lapisan apt:

1. `unattended-upgrades` boot-time meng-upgrade 241 paket dan memegang
   `/var/lib/dpkg/lock-frontend` >1 jam; `apt-get install unzip` di dalam
   `setup/xray.sh` menunggu lock TANPA batas (`DPkg::Lock::Timeout` default kosong).
   Gejala: output berhenti tepat setelah `info: Installing Xray ...`, CPU idle.
2. Mirror `*.clouds.archive.ubuntu.com` punya AAAA record tetapi VPS ini tidak punya
   route IPv6 → apt menggantung pada koneksi IPv6 yang tidak pernah selesai.
3. `bzip2` tidak terpasang di image minimal → `tar -xjf` gagal saat build Dropbear.

Perbaikan: `_apt_quiesce()` di awal install (stop `apt-daily*`/`unattended-upgrades`,
tulis `/etc/apt/apt.conf.d/99mytunnel-install` berisi `DPkg::Lock::Timeout "600"`,
`Acquire::ForceIPv4 "true"`, timeout 30s, retries 2, `DEBIAN_FRONTEND=noninteractive`),
`bzip2` masuk daftar dependensi wajib.

### BUG: Dropbear gagal build tetapi installer tetap lapor "selesai"
`if ! bash "$ETC/setup/dropbear.sh" 2>&1 | tee -a "$LOG"` memakai status `tee`
(selalu 0) → kegagalan tidak terdeteksi. Ganti dengan helper `_mt_step()` yang
mengembalikan `${PIPESTATUS[0]}`; dipakai untuk semua langkah setup (9 titik).

### BUG: build Dropbear bergantung pada paket yang tak diperiksa
Sekarang memeriksa `gcc`, `bzip2`, `zlib1g-dev` lebih dulu, memasang yang kurang,
dan berhenti dengan pesan yang menyebut paket persisnya.

### BUG: `/etc/shells` diperiksa setelah build
`ensure_shell` dipindah ke awal `main()`; tanpa `/bin/false` di `/etc/shells`
dropbear 2019 menolak login akun tunneling ("User 'x' has invalid shell, rejected")
walau password benar.

### BUG: unit systemd dropbear tidak ada di image minimal
Jika tidak ada `/etc/init.d/dropbear` maupun unit dari paket, installer menulis
unit `dropbear.service` sendiri (Type=forking, `-p <port> -b banner -P /run/dropbear.pid`)
sehingga wrapper 2019.78 benar-benar dijalankan dan port 90 listen.

### Lain-lain
- `write_config` mengisi `DROPBEAR_LISTEN_PORT`; pesan "Dropbear aktif (port )"
  tidak lagi kosong.
# CHANGELOG
## v1.10.3 — 2026-11-12 — SlowDNS benar-benar konek: compat wire + tolak upstream 53

### BUG KRITIS: SlowDNS jalan tapi klien tidak pernah bisa konek
Dua cacat yang saling menutupi di `advanced/slowdns.sh`:

1. `slowdns_install()` menulis `DNSTT_COMPAT="0"` **hardcoded** ke `slowdns.conf`,
   padahal `_slowdns_read_conf()` memakai default `"1"`. Akibatnya service tidak
   pernah diberi flag `-dnstt-compat`, jadi binary vaydns memakai format wire baru.
   `dnstt-client` standar (dan aplikasi SlowDNS/DNSTT yang beredar) gagal di
   `accept streams: noise handshake: timeout` — server terlihat "ready" di log
   padahal tidak ada satu pun sesi yang lolos. Gejala di klien: connect tapi tidak
   ada data / `Connection timed out during banner exchange`.
2. Prompt "Port SSH target [22]" menerima **53** apa adanya. Karena 53/5300 milik
   SlowDNS sendiri, `-upstream 127.0.0.1:53` membuat server meneruskan ke port
   kosong (atau ke dirinya sendiri) — tunnel mustahil konek walau flag benar.

Sekarang: `DNSTT_COMPAT="1"` ditulis eksplisit, dan port 53/5300 ditolak dengan
pesan jelas saat install.

Diverifikasi live di VPS 43.128.104.92: `dnstt-client -udp <ip>:5300 ... 127.0.0.1:7000`
→ `begin stream` + handshake SSH sampai (balasan `Permission denied (publickey,password)`
dari sshd = jalur sudah tembus).

### Catatan klien
Aplikasi klien memakai **port 53/UDP** (bukan 5300): iptables me-redirect
`PREROUTING udp dport 53 -> 5300`. 5300 hanya dipakai untuk uji langsung.
Record type harus sama dengan `RTYPE` di `slowdns.conf`; `NULL` paling kompatibel.

## v1.10.2 — 2026-11-12 — fix nginx mati: pemegang :80 di conf.d + unit ter-mask

### BUG: nginx mati setelah install, semua port 443/8080/2082/2083/8880/81 hilang
`_free_port80()` hanya menyingkirkan `/etc/nginx/sites-enabled/default`. Di Ubuntu 22.04
site bawaan ada di **`/etc/nginx/conf.d/default.conf`** (`listen 80;`) sehingga:
httpmux tetap bisa bind :80, tapi nginx gagal `bind() to 0.0.0.0:80 failed (98: Address
already in use)` → unit `nginx.service` mati. Pada VPS yang sebelumnya pernah di-mask,
`systemctl start nginx` malah menjawab `Unit nginx.service is masked` — tanpa error jelas
di akhir installer.

Sekarang:
- `_free_port80()` memindai **`/etc/nginx/sites-enabled/*` dan `/etc/nginx/conf.d/*.conf`**,
  memindahkan setiap file yang punya `listen 80` ke `/root/backup/` (nama file dipertahankan).
- `_unmask_nginx()` baru: `systemctl unmask` + `enable` bila unit ter-mask, lalu start bila
  belum aktif. Dipanggil dari `_free_port80()`.
- `enable_service()` di embedded `setup/nginx.sh` juga unmask sebelum enable, supaya
  instalasi ulang di VPS lama tidak lagi gagal senyap.

Diverifikasi di VPS 43.128.104.92: `nginx -t` OK, nginx aktif, listener 8080/2082/2083/8880/8443/81
semua kembali; simulasi `_free_port80()` memindahkan `conf.d/default.conf` tanpa menyentuh
`mytunnel.conf`.

## v1.10.1 — 2026-11-11 — data SlowDNS di output akun SSH + notifikasi Telegram

### Added
- Create/trial SSH menampilkan NS domain, tipe record, dan public key (64 hex) di output akun dan notifikasi Telegram. Private key tidak pernah ditampilkan.

## v1.10.0 — 2026-11-11 — Dropbear 2019.78 wajib, SlowDNS multi-record + public key, UDPGW publik 7300, nginx lebih aman

### Dropbear WAJIB 2019.78 (dibangun dari source)
`install_dropbear()` sebelumnya cuma `apt-get install -y dropbear` → di Ubuntu 22.04
menghasilkan **2020.81**, padahal 2019 yang dipakai klien tunneling. Sekarang:
- Unduh `dropbear-2019.78.tar.bz2` dari mirror resmi (`matt.ucc.asn.au` → fallback
  `dropbear.nl`), **verifikasi SHA256**
  (`525965971272270995364a0eb01f35180d793182e63dd0b0c3eb0292291644a4`).
- Build dengan `-fcommon` bila GCC ≥ 10 (default `-fno-common` membuat link gagal).
- Binary dipasang ke `/usr/local/sbin/dropbear-2019`; `/usr/sbin/dropbear` jadi
  **wrapper** ke binary itu, karena init.d Debian/Ubuntu menunjuk jalur tersebut —
  tanpa wrapper, service tetap menjalankan 2020.81 dari paket apt.
- Host key RSA/ECDSA dibuat otomatis. Catatan: **ed25519 tidak ada di 2019.78**
  (hanya rsa/dss/ecdsa) — jangan minta dropbearkey 2019 membuat ed25519, ia gagal.
- Idempoten: kalau `/usr/sbin/dropbear -V` sudah `v2019.*`, build dilewati.
- Verifikasi versi dilakukan lewat path absolut `/usr/sbin/dropbear`, bukan `dropbear`
  dari PATH (PATH bisa menunjuk binary paket apt).

### BUG KRITIS: login password Dropbear dimatikan `-s -g`
`DROPBEAR_EXTRA_ARGS` lama berisi `-b <banner> -s -g`. Pada Dropbear:
`-s` = matikan **semua** login password, `-g` = matikan password login untuk root
→ praktis semua akun tunneling ditolak, klien cuma melihat
`Permission denied (publickey)`. Sekarang flag itu dihapus (hanya `-b <banner>`),
ditambah komentar peringatan di script dan pemeriksaan pasca-restart yang
memunculkan error merah bila `-s`/`-g` muncul lagi.
Diverifikasi live: user password di port 90 → `LOGIN_OK`.

### Create/trial SSH memuat data SlowDNS
- Output akun dan notifikasi Telegram kini menampilkan NS domain, tipe record, dan public key (64 hex). Private key tidak pernah ditampilkan.

### SlowDNS multi-record + public key ditampilkan
- Binary server = vaydns fork (multi-record + fallback) dari release repo ini
  (tag `dnstt-multi`) dengan verifikasi SHA256 per arsitektur (amd64/arm64).
- `-record-type` mendukung **TXT, NULL, CNAME, NS, MX, SRV** — bisa dipilih saat
  instal dan panduan record DNS dicetak sesuai tipe. Aplikasi klien yang punya
  pilihan Type (Automatic/TXT/NULL/…) langsung cocok.
- Saat instal, **public key (64 hex) dicetak dalam blok menonjol** supaya bisa
  ditempel ke kolom PUBKEY aplikasi klien; `SlowDNS → status` juga menampilkannya penuh.
- Port 53 dibebaskan dari stub `systemd-resolved` dengan backup + rollback bila unduh gagal.

### UDPGW publik di UDP/7300
- Wrapper badvpn-udpgw sekarang **satu proses publik `0.0.0.0:7300`**
  (`--udp-mtu 65507`), bukan 5 listener loopback — UDP & DNS (HTTP Custom, klien
  badvpn) jalan lewat port ini.
- `ufw allow 7300/udp` dipanggil di dua tempat: `install_udpgw()` dan `setup_ufw()`
  (dulu firewall tidak pernah membuka 7300 → service aktif tapi klien tak bisa konek).

### Nginx: update CVE otomatis + aturan lebih aman
- `add_nginx_official_repo()` + `update_nginx_cve()`: repo resmi nginx.org
  ditambahkan, lalu `apt-get install --only-upgrade nginx libnginx-mod-stream`.
  Dijalankan setiap kali installer/auto-update dipanggil, jadi nginx distro yang
  membeku (Ubuntu 22.04 = 1.18.0) ikut terbarui. `nginx -t` dulu sebelum restart.
- **Port 81 tidak lagi `autoindex on`** (itu mengekspos seluruh isi `/var/www/html`).
  Sekarang `location /` mengembalikan 404 dan hanya `/myvpn-config.zip` yang dilayani,
  dengan `limit_except GET HEAD { deny all; }` + `X-Content-Type-Options nosniff`.
- Location `/whatever` tidak lagi memakai `rewrite ^/whatever$ /vmess break;`;
  pemetaan ke endpoint Xray dilakukan lewat URI di `proxy_pass`
  (`proxy_pass http://127.0.0.1:10001/vmess;`). Exact-match location tetap, tanpa
  regex yang bisa cocok ke varian path lain.

### Matrix OS disamakan dengan dukungan nyata
Preflight sekarang menerima **Debian 12/13 dan Ubuntu 22.04/24.04/26.04** (sebelumnya
Ubuntu 18/20 + Debian 11/12). Versi di luar matrix hanya jadi peringatan.

### Semua URL diarahkan ke repo `tunnel-allinone-patch`
`--help`, banner instruksi, dan default `config/repo.txt` (dipakai Auto Update)
menunjuk repo ini. Sebelumnya `repo.txt` menunjuk repo base yang tertinggal versi →
auto-update akan "menurunkan" VPS kembali ke rilis lama.

## v1.9.10 — 2026-11-11 — fix unit systemd xray-guard rusak + update-login-report gagal senyap


### Bug C — install tanpa domain mati diam-diam (ditemukan di VPS live)

Baris `MYTUNNEL_DOMAIN="${MYTUNNEL_DOMAIN:-$(cat /etc/mytunnel/domain.txt 2>/dev/null)}"`
gagal saat `/etc/mytunnel/domain.txt` belum ada (VPS fresh) dan `set -e` mematikan
installer tanpa pesan — gejala: prompt balik ke shell tepat setelah `Arch: x86_64 ✓`,
tidak ada tahap `[1/13]`. Diperbaiki dengan `|| true` pada substitution.

Dampak lanjutan bila dipaksa lewat (domain.txt diisi `-`): `xray.service` gagal start
(`/var/log/xray` owner `nobody:nogroup` → permission denied saat buka `access.log`),
nginx `mytunnel.conf` tak dibuat karena guard `die "Domain belum diisi"`, WS 502.
**README kini menetapkan domain WAJIB diisi saat install.**

### Bug A — unit systemd tanpa `[Unit]` / `[Install]`

`mytunnel-xray-guard.service` dan `.timer` ditulis dari heredoc yang tidak
mencantumkan header `[Unit]`, dan timer tidak punya `[Install]`. systemd
menolak unit tanpa section valid → watchdog xray mati senyap (`cat >` sukses,
tapi timer tidak pernah jalan). Diperbaiki di `install.sh` dan
`xray-guard-install.sh`.

### Bug B — `update-login-report.sh` hanya extract 3/6 file, exit 0

Split heredoc memakai `"<<'__EMBED_EOF__'"` tanpa spasi, padahal sebagian blok
ditulis `<< '__EMBED_EOF__'` → `config.conf`, `menu.sh`, `uninstall.sh`
terlewat tanpa peringatan. Regex `cat >` juga tidak match path berkutip.
Ditambah hard-fail bila jumlah file tidak sama dengan `path_map`.

### Ikut diperbaiki

- `.githooks/pre-commit`: pola PAT hanya `gh[pousr]_` → fine-grained
  `github_pat_...` lolos. Diperluas.
- `.githooks/pre-commit`: `verify.sh`, `update-login-report.sh`,
  `xray-guard-install.sh` masuk daftar cek SHA256SUMS.
- README: versi disinkronkan, entri SHA256SUMS 12, instruksi
  `git config core.hooksPath .githooks` (hook tidak aktif bawaan).

---


## v1.9.9 — 2026-11-04 — fix xray gagal start: log dir salah owner (User=xray)

### Fixed
- **"✗ Service xray gagal start" di setiap install baru.** Installer resmi Xray
  (XTLS/Xray-install versi sekarang) membuat systemd unit dengan
  `User=xray`/`Group=xray` dan `/var/log/xray` mode **700 xray:xray**. Tapi
  `setup/xray.sh` `write_config()` melakukan `chown nobody:nogroup` ke dir dan
  file log itu — user `xray` jadi tidak bisa buka `access.log` sama sekali, dan
  xray mati saat start:
  `Failed to start: main: ... app/log: failed to initialize access logger >
  open /var/log/xray/access.log: permission denied`.
  (Reproduksi + verifikasi pesan error dilakukan dengan xray 1.8.24 asli.)
  Sekarang owner log dir/file diambil dari unit asli (`User=`/`Group=`), fallback
  `nobody` untuk unit lama.
- **`validate_config()` tidak pernah bisa gagal**: `if ! xray run -test ... | tee`
  — status pipeline = status `tee` (selalu 0), jadi config rusak lolos validasi
  dan baru bunuh xray di `enable_service`. Diganti cek `PIPESTATUS[0]`
  (diverifikasi: config rusak -> exit 23 sekarang terdeteksi).


## v1.9.8 — 2026-11-04 — fix installer mati senyap setelah preflight (VPS baru)

### Fixed
- **Installer mati TANPA pesan error tepat setelah preflight** (gejala: prompt
  balik ke shell segera setelah baris `Arch: x86_64 ✓`, tidak ada tahap
  `[1/13]`). Penyebab: baris
  `MYTUNNEL_DOMAIN="${MYTUNNEL_DOMAIN:-$(cat /etc/mytunnel/domain.txt 2>/dev/null)}"`
  di bawah `set -e` — di VPS baru file itu belum ada, `cat` exit 1, status
  assignment ikut 1, script mati. Ditambah `|| true` di dalam substitution.
  Bug ini ada sejak base dan juga memengaruhi v1.9.7: fresh install
  `MYTUNNEL_YES=1 bash install.sh` (tanpa `MYTUNNEL_DOMAIN`) tidak pernah
  mencapai tahap apa pun. Diuji live mode prefix: install penuh exit 0,
  `domain.txt` = `-`, cert self-signed CN=IP, nginx `server_name` IP,
  10 inbounds xray, watchdog terpasang.


## v1.9.7 — 2026-11-04 — domain boleh dilewati saat install + xray watchdog

### Added
- **Domain bisa dilewati saat install**: prompt `setup/domain.sh` menerima Enter
  kosong -> `domain.txt` diisi `-`, install lanjut dengan cert self-signed
  (CN=IP VPS) dan nginx `server_name` pakai IP. Non-interaktif: `MYTUNNEL_YES=1`
  tanpa `MYTUNNEL_DOMAIN` (atau `MYTUNNEL_SKIP_DOMAIN=1`) langsung lewat tanpa
  prompt. Domain asli dipasang belakangan lewat **menu -> 6 FEATURES -> 9 Change
  Domain VPS** (`features/domain.sh`: issue cert LE domain baru, rollback
  otomatis kalau cert/nginx gagal).
- **Xray watchdog** (`setup/xray-guard.sh` + `mytunnel-xray-guard.timer`, cek
  tiap 60 detik): bila xray tidak aktif, config diuji dengan `xray run -test`;
  kalau rusak, backup valid terbaru di-restore (config rusak disimpan sebagai
  `.broken-*`) lalu xray di-restart. Semua tindakan dicatat di
  `/var/log/mytunnel.log` dengan prefix `xray-guard:`. Terpasang otomatis saat
  install/reinstall (production only).

### Fixed
- **cert.sh `_log` tidak terdefinisi** -> `set -e` mematikan script (exit 127)
  tepat di path fallback self-signed. Sekarang `_log` punya fallback lokal.
- **cert.sh fallback ACME gagal pakai `$CERT_CRT`/`$CERT_KEY` yang tidak pernah
  di-set** (fungsi hanya mendefinisikan `cert_crt`/`cert_key`), sehingga
  `openssl -keyout ""` gagal -> `die "Self-signed ikut gagal dipasang"` ->
  install mati di tahap [7/13] setiap kali Let's Encrypt gagal (rate limit 429,
  DNS belum propagasi). Variabel diperbaiki ke `cert_crt`/`cert_key`.
- **acme.sh email `admin@-`** saat domain belum diset -> diganti `example.com`.


## unreleased — preflight minim-error + verify.sh (gRPC 8444 sudah di rilis ini)

### Added
- **`preflight()` di `install.sh`**, dijalankan paling awal, berhenti dengan pesan
  jelas bila syarat wajib gagal. Cek: OS Ubuntu/Debian didukung; root; nginx
  terpasang **dan** modul stream (static atau `modules-enabled` + `load_module`);
  port **80/443/8443/8444/9443** tidak dipakai proses lain (proses mytunnel
  sendiri saat reinstall dikecualikan); domain resolve ke IP publik VPS
  (**peringatan**, bukan fatal, bila via Cloudflare); internet & disk (≥2 GB,
  fatal) / RAM (<512 MB, peringatan). Mode `MYTUNNEL_PREFIX` melewati cek sistem
  agar test tetap jalan.
- **`verify.sh`** (root repo, dipanggil di akhir `install.sh`, bisa manual).
  Mencetak PASS/FAIL untuk: `nginx -t`; nginx & xray active; map stream
  (`~^h2$`/`~^h2,http/1\.1$` -> 8444 di paling atas, `9443` tanpa http2, `8444`
  ssl http2); listener 8444 & 9443; `openssl -alpn h2` ke :443 = `h2`; ALPN
  `h2,http/1.1` mendarat di 8444 (`ss`); WS `101` untuk `/vmess` `/vless`
  `/trojan` (`--http1.1`); SSH-WS `101` & SSH-TLS terbuka; sertifikat valid
  (tanggal expired). Ringkasan akhir: `SEMUA LULUS` atau daftar gagal + perintah
  perbaikan. Exit 1 bila ada FAIL. Diuji live: **18 PASS, 0 FAIL**.

### Changed
- **Panduan preflight lama (inline) diganti `preflight()`** yang mencakup OS,
  root, nginx+stream, port 8443/8444/9443, dan domain resolve.
- Semua perubahan nginx (via `configure-final-443.sh`) tetap: backup `.off`,
  tulis lewat file temp, `nginx -t`, baru reload; gagal -> restore otomatis dan
  cetak penyebab.

### Fixed
- **gRPC (VMess/VLESS/Trojan) tidak konek lewat port 443.** Klien gRPC (mis.
  v2rayNG mode `gun`) menawarkan ALPN `h2,http/1.1` (dan sebagian `h2` saja),
  sementara map `$ssl_preread_alpn_protocols` mengarahkannya ke
  `127.0.0.1:9443` yang hanya `listen ... ssl` **tanpa `http2`**. Negosiasi jatuh
  ke HTTP/1.1 sehingga gRPC — yang mewajibkan HTTP/2 — tidak pernah terbentuk.
  Gejala di klien: "Unable to detect internet connection" walau server menerima
  koneksi TLS. Diverifikasi live: `curl --http2` ke `:8443` menjawab HTTP/2 (rute
  benar), sedangkan ke `:443` gagal total; `tshark` membuktikan klien WS nyata
  mengirim `http/1.1` polos dan klien gRPC mengirim `h2,http/1.1`.

### Changed
- **Listener baru `127.0.0.1:8444` bersifat gRPC-only:** `listen ... ssl http2`,
  **tanpa** `include mytunnel-locations.inc` dan **tanpa location WS** — cuma
  `grpc_pass` ke `10011/10012/10013` (termasuk varian `.Tun`) plus `404` di `/`.
  Cert, ciphers, `ssl_protocols`, `ssl_session_cache` **disamakan** dengan blok
  8443; `server_name` diambil otomatis dari blok 8443 (tidak ada domain
  hardcoded).
- **Map stream (urutan tepat):**
  `~^h2$` -> `8444`, `~^h2,http/1\.1$` -> `8444`,
  `~\bh2\b` -> `9443`, `~\bhttp/1\.1\b` -> `9443`, `default` -> `4443`.
  `9443` tetap tanpa `http2` (melayani WS/HTTP-1.1).
- **Idempotent:** dijalankan 2×+ tidak menambah server 8444 atau entri map
  dobel. `apply_grpc_h2_route()` membuang entri `~^h2$`/`~^h2,http/1.1$` lama
  yang menunjuk port lain lalu menulis ulang versi benarnya. Satu mekanisme
  (awk -> `mktemp` -> `mv`), **tidak** menggabungkan `sed -i` dengan `awk`.
  `nginx -t` sebelum reload; gagal = rollback otomatis. Backup
  `/root/nginx-backup/*.off`.

### Risiko
- **Klien WS yang mengirim ALPN `h2,http/1.1` akan mendarat di `8444` dan
  mendapat `404`.** Diuji pada klien WS nyata yang dipakai (v2rayNG) yang
  mengirim `http/1.1` polos, jadi tidak terpengaruh. Tetapi aplikasi WS lain
  yang menawarkan `h2,http/1.1` (beberapa browser/klien gabungan) tidak akan
  mendapat WS di jalur ini. Bila perlu, pisahkan lewat SNI khusus (mis.
  `grpc.<domain>` -> 8444) alih-alih memakai `h2,http/1.1`.

### Tested
- Ubuntu (24.04) + nginx 1.18.0, live: WS `/vmess` `/vless` `/trojan` @443
  balas `101`, `/ssh-ws` `101`, SSH-TLS 444 & SSH 22 terbuka, `-alpn h2` ke
  `8444` = `h2`, `9443` tetap tanpa `http2`, koneksi gRPC mendarat di `8444`.
- Nginx versi lebih baru mungkin perlu sintaks `http2 on;` (directive terpisah)
  alih-alih flag `http2` pada `listen`.
- Verifikasi live: WS `/vmess` `/vless` `/trojan` @443 = `101`; koneksi gRPC
  mendarat di `8444`; ALPN `h2`/`h2,http/1.1` -> `8444`, `http/1.1` -> `9443`.


## v1.9.6 — 2026-10-12 — fix stream module dynamic + cert 429 tidak lagi matiin install
### Fixed
- **`--with-stream=dynamic` (Debian 12)**: `nginx -V 2>&1 | grep -q -- '--with-stream'`
  ikut match nilai dynamic, sehingga guard `ensure_nginx_stream()` langsung `return 0`
  dan `load_module` tidak pernah ditambahkan — padahal modul `.so` tetap WAJIB dimuat
  lewat `load_module`. Akibatnya blok `stream { listen 443; ssl_preread on; }` tidak
  aktif, `configure-final-443.sh` rollback, dan **443 tidak listen** (80 tetap jalan
  karena tidak butuh modul stream). Semua guard diganti ke `grep -q -- '--with-stream[^=]'`
  supaya hanya static compile yang boleh skip `load_module`.
- **cert 429 / install-cert gagal tidak lagi mematikan install**: log VPS menunjukkan
  `cat: /root/.acme.sh/<domain>_ecc/fullchain.cer: No such file or directory` →
  `✗ File cert kosong setelah issue` → `die`, sehingga VPS terpasang tanpa cert apa pun
  dan 443 mati total (bukan cuma warning browser). `--install-cert` yang gagal atau
  staging yang kosong sekarang memanggil `fallback_selfsigned()` (self-signed 365 hari,
  backup + chmod yang benar) lalu `return 0`, jadi install lanjut dan 443 tetap listen TLS.

### Catatan
- Kegagalan **429 rate limit** Let's Encrypt (`new-certificates-per-exact-set-of-identifiers`,
  5 per 168 jam) adalah limit eksternal LE, tidak bisa diperbaiki dari repo. Reset otomatis
  setelah 7 hari; lalu ulangi dengan `bash /etc/mytunnel/setup/cert.sh --force`.

## v1.9.5 — 2026-10-12 — fix port 443 tidak listen: modul stream nginx tidak pernah dimuat
### Fixed
- **Penyebab utama 443 mati (80 tetap konek)**: nginx dari repo distro (`apt-get install nginx`)
  TIDAK otomatis memuat modul stream. Blok `stream { listen 443; ssl_preread on; }` yang
  dipasang `configure-final-443.sh` membuat `nginx -t` gagal ("unknown directive \"stream\""),
  sehingga script rollback dan 443 tidak pernah listen. HTTP di port 80 tidak butuh modul
  stream — itu sebab 80 konek sementara 443 mati.
- `setup/nginx.sh` `install_nginx()` sekarang memanggil `ensure_nginx_stream()`:
  pasang `libnginx-mod-stream` kalau belum ada, dan tambahkan `load_module modules/ngx_stream_module.so;`
  di baris paling atas nginx.conf (posisi wajib, sebelum `events`/`http`),
  lalu validasi `nginx -t`.
- Install nginx baru memakai `apt-get install -y nginx libnginx-mod-stream` (fallback ke `nginx` saja).
- `configure-final-443.sh` `check_prereq()` tidak lagi `die` kebetulan user tidak punya modul —
  sekarang memasang otomatis, dan menambah `load_module` ke nginx.conf sebelum melanjutkan.
- `configure-final-443.sh` (file fisik) disinkronkan dengan versi embed di `install.sh`.

### Verifikasi
- `bash -n` semua file OK; harness `MYTUNNEL_PREFIX --no-deps` OK.
- `nginx.sh` & `configure-final-443.sh` hasil harness memuat guard (7 dan 9 ref).
- Simulasi penambahan `load_module`: masuk di baris 1, sebelum `events`/`http` — divalidasi grep.

## v1.9.4 — 2026-10-12 — fix Change Domain dan --force + cert.sh idempoten
### Fixed
- `features/domain.sh` (menu 6 -> 9 Change Domain VPS): parsing `CN` dari subject cert
  pakai `sed "s/.*CN *= *//"` yang menghasilkan `new.example.com, o = mytunnel` ketika
  subject mengandung field lain (contoh `O=MyTunnel` dari self-signed). Akibatnya validasi
  "cert harus milik domain baru" salah tolak dan menggagalkan ganti domain. Sekarang pakai
  `-nameopt RFC2253` + split per-field, teruji 3 kasus (CN saja, CN+O, CN huruf besar).
- `setup/cert.sh` tidak punya parser argumen sama sekali, padahal v1.9.3 memberi instruksi
  `bash $ETC/setup/cert.sh --force` ke user. Ditambahkan parser `--force` (paksa issue ulang
  walau cert masih ada) dan `--help`.
- `cert.sh` sekarang idempoten: kalau cert untuk domain itu sudah ada dan masih valid,
  issue di-skip (bukan re-issue tiap kali dipanggil dari step install/change-domain).
  `--force` melewati skip ini — dipakai untuk mengganti self-signed fallback dengan LE asli.
- Pesan setelah fallback self-signed sekarang menyebut reset rate limit 7 hari secara eksplisit.

## v1.9.3 — 2026-10-12 — cert gagal (429 rate limit LE) tidak lagi mati total install
### Fixed
- `setup/cert.sh`: saat ACME gagal (HTTP 429 `too many certificates (5) already issued for
  this exact set of identifiers`, atau DNS belum propagasi), script sebelumnya memanggil
  `die` = `exit 1` sehingga seluruh install berhenti. Sekarang pasang **self-signed
  365 hari** sebagai fallback (cert lama di-backup `.bak-<timestamp>` dulu) dan install
  lanjut sampai selesai, supaya 443/8443/80 tetap listen dan menu/xray/dropbear tetap terpasang.
- Pesan error sekarang menyebut rate limit 5/domain/minggu secara eksplisit, dan petunjuk
  ulangi issue manual: `bash $ETC/setup/cert.sh --force`.
- Cert self-signed tetap memicu warning 'untrusted' di browser (wajar) — ini memang
  fallback sementara sampai rate limit LE reset (7 hari) dan issue ulang dimasukkan.

### Catatan
- Kegagalan 429 Let's Encrypt bukan bug script dan tidak bisa diperbaiki dari repo:
  limit LE = 5 sertifikat per exact set identifier per minggu. Solusi: tunggu reset
  seminggu, atau pakai domain lain, atau pakai DNS-01 challenge.

## v1.9.2 — 2026-10-12 — fix 443 tidak listen + login-report tidak bisa menerima token bot
### Fixed
- **PORT 443 tidak pernah ter-setup**: embed `configure-final-443.sh` menulis ke
  `${BASE}/configure-final-443.sh` yang saat produksi = `/configure-final-443.sh` (root FS),
  tapi `chmod` diarahkan ke `/root/configure-final-443.sh`. File tidak executable sehingga
  blok step `[9d/13]` selalu dilewati. Sekarang keduanya pakai variabel `F443` yang sama
  (`${BASE:-/root}/configure-final-443.sh`).
- step `[9d/13]` sekarang memverifikasi `ss -tln | grep ':443 '` dan `:80 ` setelah setup;
  kalau belum listen, paksa buka UFW + reload nginx, jalankan ulang httpmux, lalu laporkan
  status final ke layar (tidak diam-diam gagal).
- **LOGIN REPORT tidak bisa menerima token bot**: `menu 1` memanggil `lr_sanitize` yang
  tidak pernah didefinisikan di `common.sh`/`collector.sh`/`core.sh`. Akibatnya
  `t=$(lr_sanitize "$t")` menghasilkan string kosong dan token yang diketik user hilang.
  Fungsi `lr_sanitize` sekarang ada (buang karakter di luar `[0-9A-Za-z:_-]`).
- `lr_load_conf` kini memanggil `lr_defaults` lebih dulu: semua variabel config punya nilai
  default, jadi `set -u` tidak lagi melempar "unbound variable" (XRAY_CONFIG, XRAY_ACCESS_LOG,
  dll) saat `/etc/login-report/config.conf` hilang atau rusak.
- `lr_set_conf` membuat `config.conf` dari template default bila file belum ada, sehingga
  menu 1 tetap bisa menyimpan token pada instalasi baru.
- `lr_log` memilih path fallback writable (`$TMPDIR/login-report.log`) bila `/var/log` tidak bisa ditulis.
- `LR_BASE`/`LR_CONF`/`LR_LOG` di `core.sh`, `menu.sh`, `common.sh` kini memakai `${VAR:-default}`
  agar bisa di-override (test mode) tanpa mengubah perilaku produksi.
- dispatcher menu 10 tidak lagi membuang stderr (`2>/dev/null` dihapus) dan punya fallback ke
  `/etc/mytunnel/login-report/menu.sh`; kode error ditampilkan sebagai `rc=$?`.
- semua fungsi `lr_*` yang dipanggil sudah terdefinisi (scan otomatis: 0 missing).

## v1.9.1 — 2026-10-12 — install 1-perintah tanpa setting lanjutan + login-report token bisa dimasukan
### Fixed
- login-report: `/etc/login-report/config.conf` dijamin ada saat install. Sebelumnya blok copy
  hanya jalan kalau `[ -d /etc/login-report ]` dan `install -d -m 700` gagal (non-root),
  sehingga `lr_load_conf` gagal "config tidak ada" dan menu (10) tidak bisa menerima
  BOT_TOKEN / CHAT_ID. Sekarang ada fallback default berisi semua key.
- login-report: semua path install ikut prefix (`$BASE`) sehingga test mode `MYTUNNEL_PREFIX`
  tidak lagi gagal "Permission denied" saat menulis unit systemd.
- domain & brand diambil otomatis dari env atau `/etc/mytunnel/*.txt`; tidak ada lagi
  prompt konfirmasi install yang menggantung di piped input.
- brand fallback stabil ke "SUNEK VPN" (bukan "My Brand").

## v1.9.0 — 2026-10-11 — brand permanen total (tidak bisa diubah lewat jalur mana pun) + bersihkan referensi skrip lama
### Fixed
- brand permanen 4 lapis: chattr +i, canon 600 root-only, cron tiap menit, dan bg_set() menolak tanpa jalur bypass
- --brand dan MYTUNNEL_BRAND sekarang diabaikan bila brand.txt sudah immutable
- embed config/brand.txt tidak menimpa file yang sudah terkunci
- menu SET BRAND NAME (8) sepenuhnya read-only; jalur "FORCE" dihapus (dead code)
- bg_set() tidak lagi menerima parameter force sama sekali

## v1.8.1 — 2026-10-11 — brand permanen total + login-report menu 10
### Fixed
- brand_guard: brand.txt dipaksa kembali ke canon tiap menit, canon jadi 600 root-only
- brand_guard: bg_set menolak kalau sudah terkunci (return 2) — tak bisa diubah tanpa FORCE
- menu SET BRAND NAME (8) jadi read-only; perlu ketik FORCE eksplisit untuk mengubah
- config/repo.txt default disamakan ke tunnel-allinone (bukan mytunnel-installer)
### Added
- login-report: menu 10 (laporan user aktif ke Telegram via systemd timer)
- login-report: core.sh dipasang 755 (fix systemd 203/EXEC)

## v1.8.0 — 2026-10-09 — IP publik salah baca (IPv6) + xray live-apply tanpa restart
### Fixed
- `get_ip_cached()` dan `ah_get_ip()` memakai `curl` tanpa `-4`, sehingga di host
  dual-stack hasilnya bisa IPv6 (`2400:6180:...`) dan muncul di menu IP/client,
  WARP, SlowDNS, dan notifikasi bot. Keduanya sekarang memaksa IPv4 (`curl -s4`)
  dan mem-parse ulang hasilnya dengan regex IPv4; fallback `hostname -I` (yang
  mengembalikan IPv6 lebih dulu) juga difilter.
- `features/domain.sh`: `pub_ip` untuk pengecekan A-record ikut dipaksa IPv4 —
  sebelumnya bisa membandingkan A-record IPv4 dengan IP publik IPv6 dan
  melaporkan mismatch palsu.

### Added
- `_xray_live_apply()` di `lib/xray_helpers.sh`: add/del client dikirim ke instance
  Xray yang sedang berjalan lewat Xray API (HandlerService, `xray api adu/rmu`),
  lalu menulis flag `/run/mytunnel-live-apply` yang membuat `xray_reload()` melewati
  restart. Klien baru langsung aktif tanpa memutus sesi lain.
- `cron/bot_notify.sh` memuat `features_helpers.sh` (helper `fh_*` sebelumnya tidak
  tersedia di konteks cron).

### Verified (live, VPS <VPS-IP>)
- IPv6 `<VPS-IPv6>` -> regex tolak (`[]`), IPv4 -> `<VPS-IP>`.
- `ah_get_ip` = `get_ip_cached` = `<VPS-IP>`.
- Repo <-> VPS: 70/70 file embedded identik (diff per-blok + tar pull ulang).
- `bash -n` seluruh 70 blok + `install.sh` = 0 error.

## v1.7.1 — 2026-10-08 — Port 80 (SSH + enhanced mode) tidak pernah terpasang
### Fixed
- `setup/httpmux.sh` ada di installer tapi **driver tidak pernah memanggilnya**, jadi
  `mytunnel-httpmux` (listener :80) tidak pernah jalan. Akibatnya port 80 dipegang
  server default bawaan paket nginx (`sites-enabled/default`, halaman "Welcome to nginx")
  dan bukan oleh mux mytunnel -> SSH port 80 dan enhanced mode HTTP Custom mati.
  Driver sekarang memanggilnya di tahap baru `[9c/13]` setelah nginx + tlsmux.
- `install_httpmux()` sekarang menjalankan `_free_port80` lebih dulu: `sites-enabled/default`
  yang memegang `listen 80 default_server` dipindah ke `/root/backup/` lalu nginx direload.
  Tanpa ini httpmux gagal bind :80 (EADDRINUSE).
- `mytunnel-httpmux.py` hanya punya dua cabang (CONNECT -> SSH, sisanya -> nginx :8080),
  sehingga **raw SSH** di port 80 (klien mengirim banner `SSH-2.0-...`) dilempar ke nginx
  dan menggantung sampai timeout. Ditambah deteksi banner SSH + cabang ketiga
  `is_rawssh` yang meneruskan langsung ke SSH :22. Loop pembaca header juga berhenti
  lebih awal saat melihat banner SSH (banner tidak pernah memuat `\r\n\r\n`, jadi
  tanpa itu selalu menunggu sampai timeout).
- Peringatan "masih ada listener di :80" tidak lagi muncul saat httpmux sendiri yang
  memegang port itu.

### Verified (live, VPS <VPS-IP>, dari host luar)
- `mytunnel-httpmux` active, listener `0.0.0.0:80`; `/etc/nginx/sites-enabled/` kosong.
- HTTP biasa :80 -> 204 (diteruskan ke nginx :8080).
- Raw SSH :80 -> banner `SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.17` + key exchange;
  `ssh -p 80` dari luar berhasil sampai MOTD.
- CONNECT enhanced :80 -> `HTTP/1.1 200 Connection Established` + banner SSH.
- `bash -n` + shellcheck -S error = 0 (install.sh); python `py_compile` OK.

## v1.7.0 — 2026-10-08 — Fix UDP-Custom (1-65535) tidak pernah terpasang
### Fixed
- `setup/udp-custom.sh` menunjuk URL rilis yang **404**
  (`.../releases/latest/download/udp-custom`) sehingga binary tidak pernah terunduh.
  Diganti ke lokasi file yang benar + **SHA256 dipin** dan diverifikasi sebelum
  binary dipasang (gagal = batal, tidak dieksekusi).
- `--listen $range` adalah flag yang **tidak ada** di binary ePro v1.4. Field
  `listen` hanya menerima **satu port**; rentang 1-65535 ditangani binary lewat
  iptables DNAT (PREROUTING) untuk semua port kecuali `--exclude`.
  Unit systemd diperbaiki jadi `server --config <json> --exclude <ports>`.
- Config JSON `/etc/udp/config.json` tidak pernah dibuat (script lama hanya menulis
  file shell vars). Sekarang dibuat dengan `listen`, buffer, dan auth.
- Rule firewall tidak pernah ditambahkan sehingga UDP tetap diblokir. Karena DNAT
  terjadi sebelum filter/INPUT, firewall melihat port hasil terjemahan — jadi rule
  yang benar hanya `LISTEN_PORT/udp` (bukan seluruh rentang). `ufw allow` ditambah
  otomatis (install) dan dihapus saat uninstall.
- `_status` / `_install` / `_uninstall` dirapikan: cek SHA, laporan jumlah DNAT,
  pembersihan DNAT saat uninstall, perbaikan interpolasi warna (`${RED:-...}`) yang
  kehilangan kurung kurawal.
- `_mt_port_active`: kenali `udp-custom` di samping `mytunnel-udp-custom`.

### Verified (live, VPS <VPS-IP>)
- `udp-custom` active, listen UDP :36712; 22 DNAT rule (1-65535 minus exclude).
- SHA256 binary cocok dengan yang dipin.
- Paket uji dari luar ke port acak dalam rentang: DNAT + INPUT ACCEPT naik,
  tidak ada UFW BLOCK, sampai ke socket aplikasi.
- `bash -n` + shellcheck -S error: 0 pada install.sh dan script embedded.

## v1.6.2 — 2026-10-08 — Notif recovery disamakan + hapus ssh_compact_line
### Changed
- `do_recovery()` (menu SSH no. 11/12): notif Telegram kini pakai
  `ah_notify_admin_mono "$(ssh_account_block ...)"` -> blok penuh mono per baris,
  sama seperti create/trial (sebelumnya satu baris `host:443@u:p & host:80@u:p`).

### Removed
- `ssh_compact_line()` — sudah tidak dipakai siapa pun (dead code).

## v1.6.1 — 2026-10-08 — Baris ringkas SSH dipisah jadi 2 baris
### Changed
- `ssh_account_block()`: baris ringkas akun SSH kini **dua baris terpisah**
  (`host:443@user:pass` lalu `host:80@user:pass`), bukan satu baris digabung spasi.
- Di Telegram, tiap baris tetap dibungkus `<code>` sendiri -> dua chip mono terpisah.

## v1.6.0 — 2026-10-08 — Blok akun SSH (mono per baris) + create/trial
### Added
- `ssh_account_block()` di `lib/ssh_helpers.sh`: cetak blok akun SSH persis
  (HOST/Username/Password, Expired, TLS/NoneTLS/Any/OpenSSH/Dropbear, lalu
  SlowDNS/UDP-Custom/OHP+SSH/Squid/UDPGW/OpenVPN TCP+SSL+UDP+DNS/OHP+OVPN,
  baris ringkas `host:443@user:pass  host:80@user:pass`, dan link config).
  Nilai port dibaca dari `ports.conf` (dinamis).
- `ah_notify_admin_mono()` di `lib/advanced_helpers.sh`: kirim blok ke Telegram
  dengan tiap baris dibungkus `<code>` (parse_mode=HTML) -> mono per baris,
  bukan satu code block `<pre>`. Escape `&`/`<`/`>`; fallback teks biasa.

### Changed
- `print_ssh_account_info()` = jarak + `ssh_account_block` + jarak (terminal).
- Notif Telegram saat **create** dan **trial** akun SSH kini mengirim blok lengkap
  sebagai mono per baris (sebelumnya hanya baris ringkas).
- Pemisah blok pakai 36 tanda minus biasa (`------------------------------------`),
  bukan karakter box.

### Unchanged
- Service, port, config VPS: tidak diubah (hanya file di `/etc/mytunnel`).
- `main` tidak disentuh; kerja ini di branch `final-443-stream`.

### Verified (live, VPS <VPS-IP> / <DOMAIN>)
- Blok persis sesuai spec: dash 36, label rata kolom 16, dua spasi di baris ringkas.
- Telegram API balas `"ok":true`; payload `<code>...</code>` per baris.
- `ssh_create` dgn username yang sudah ada -> pesan error + exit 2, DB tidak bertambah.
- `bash -n` + shellcheck -S error: 0.

## v1.5.0 — 2026-10-08 — Baris ringkas akun SSH + notif Telegram mono
### Added
- `ssh_compact_line(user, pass)` di `lib/ssh_helpers.sh`: hasilkan satu baris ringkas
  `host:TLS@user:pass & host:NONTLS@user:pass` (port diambil dari `ports.conf`,
  ambil port pertama dari `TLS_PORT` dan `NONTLS_PORT`).
- `print_ssh_account_info` mencetak baris ringkas itu di akhir blok (terminal).

### Changed
- Notif Telegram saat buat akun SSH (create/trial/recovery) kini mengirim HANYA baris
  ringkas dalam mono (inline code), bukan seluruh blok `Account Created Successfully`.
  Contoh: `` `host:443@user:pass & host:80@user:pass` ``

### Verified
- Harness: baris ringkas = `<DOMAIN>:443@<user>:<pass> & <DOMAIN>:80@<user>:<pass>`;
  notif Telegram = `` `<DOMAIN>:443@<user>:<pass> & <DOMAIN>:80@<user>:<pass>` ``;
  blok terminal tetap tampil + baris ringkas di akhir. `bash -n`/shellcheck -S error 0.

## v1.4.0 — 2026-10-08 — Perbaikan stunnel/tlsmux + guard listen 443 + label vless
### Fixed
- **CRITICAL** `configure-final-443.sh`: `apply_http_tls_listen()` sekarang MENGHAPUS
  `listen 443` / `listen [::]:443` dari `mytunnel.conf` saat menambah `listen 127.0.0.1:9443`.
  Sebelumnya 443 dipegang nginx (http) DAN blok `stream ssl_preread` -> nginx gagal start
  (`bind() to 0.0.0.0:443 failed (98)`) saat reload/restart. Terverifikasi live: skenario
  regresi (listen 443 ada) kini lolos, nginx tetap active.
- `setup/tlsmux.sh`: kini self-contained — tulis `mytunnel-tlsmux.py`, bikin systemd unit
  `mytunnel-tlsmux.service`, install stunnel4 (apt), tulis `/etc/stunnel/stunnel.conf`
  (`accept 127.0.0.1:4443 -> 127.0.0.1:1443`), bikin `stunnel.pem` (cert LE, fallback
  self-signed), bikin unit `mytunnel-stunnel.service`, matikan SysV `stunnel4`.
  Sebelumnya file ini hanya menulis python + chmod; tidak ada unit/conf.

### Changed
- `install.sh`: `setup/tlsmux.sh` kini DIPANGGIL di driver sebagai `[9b/13]` (setelah nginx).
  Sebelumnya ter-embed tapi tidak pernah dieksekusi -> stunnel tak terpasang, prasyarat
  `configure-final-443.sh` tidak terpenuhi.
- Label output create VLESS disederhanakan jadi 5 (sesuai transport yang tersisa):
  `VLESS WS TLS`, `VLESS WS NO TLS`, `VLESS GRPC`, `VLESS Upgrade TLS`, `VLESS Upgrade NO TLS`.
  Baris label XHTTP yang tersisa (dead, tanpa link pasangannya) dihapus.

### Verified (live, VPS <VPS-IP> / <DOMAIN>)
- stunnel dihapus (apt remove) -> `tlsmux.sh` memasangnya kembali; unit tlsmux+stunnel active,
  listen 127.0.0.1:1443 dan 127.0.0.1:4443.
- tlsmux routing: banner SSH -> sshd (`SSH-2.0-OpenSSH_8.9p1`), HTTP -> nginx 8080 (204).
- Regresi listen 443: `configure-final-443.sh` menghapus 443, `nginx -t` lulus, nginx active.
- Idempoten: run kedua -> "sistem sudah memakai konfigurasi final — tidak ada yang diubah".
- Transport: WS 443, gRPC 443 pass (exit IP <VPS-IP>); ALPN h2 -> 9443; no-ALPN -> stunnel 4443.

## v1.3.0 — 2026-10-08 — Hapus XHTTP (tidak kompatibel)
### Removed
- XHTTP transport dihapus total dari stack (9 inbounds: ws/grpc/httpupgrade, sebelumnya 12).
- Inbound `vmess-xh`/`vless-xh`/`trojan-xh` (port 10031-10033) dihapus dari config Xray.
- nginx `location /xvmess`, `/xvless`, `/xtrojan` dihapus dari mytunnel-locations.inc.
- Link generator: 2 baris `type=xhttp` per akun vless dihapus; menu info `path xhttp` dihapus.
- Doctor check: ambang "PARSIAL" 4 -> 3 transports.
- Fungsi `_proto_xhttp_path()` dihapus.

### Why
Xray server (26.3.27) memakai `xhttp` dengan path dinamis UUID (`/<uuid>?x_padding=`),
sementara config memakai path statis `/xvmess`. Hasil uji live: handshake selalu 404
dari Xray (nginx routing sudah benar, terbukti via debug log `test location`).
Tidak memperbaiki tanpa menyelaraskan versi klien/server, jadi XHTTP dihapus.

### Verified (live, VPS <VPS-IP> / <DOMAIN>)
- WS 443, WS 8443, gRPC 443, HTTPUpgrade 443: exit IP <VPS-IP> (PASS)
- ALPN `h2`/`http/1.1` -> nginx 9443; tanpa ALPN -> stunnel 4443 (PASS)
- `bash -n` exit 0, shellcheck -S error exit 0, test-mode install PASS

## v1.2.0 — 2026-10-08 — Final 443 stream + traffic fix
### Added
- `configure-final-443.sh` as a separate, idempotent final-443 migration.
- nginx `stream ssl_preread`: ALPN `h2`/`http/1.1` to local `9443`; legacy fallback to stunnel `127.0.0.1:4443`.
- nginx `worker_connections 4096` and `worker_rlimit_nofile 65535`.
- Persistent conntrack tuning: `nf_conntrack_max=65536`, `nf_conntrack_tcp_timeout_established=7200`.
- Timestamped backups, `--dry-run`, `--rollback`, automatic rollback on failed `nginx -t`.

### Fixed
- Traffic iface auto-detect (`_traffic_iface`, `ip route` default) — replaces hardcoded `<iface>` that broke on `eth0`/`<iface>`/`ens18` VPS.
- WIB day bucket single source of truth (`_traffic_day_idx`) — `get_traffic_day`, `get_traffic_rx_tx`, and fallback now read the same `day[]` index (previously inconsistent `-1` vs `-2`).
- `get_traffic_*` use `vnstat --json` + `jq` (robust field mapping vs `--oneline | awk -F';'`); `jq` guard added to fallback.
- `curl -4` on all Telegram API calls (avoids IPv6 failure path).
- Bot long-polling: persist `OFFSET=$((update_id+1))` per update — prevents reprocessing the same message.

### Note
- Traffic helpers verify: `bash -n` OK, shellcheck 0 error, 0 hardcoded iface, day-index unit tests 4/4 PASS.
- Full 443 stream path (nginx `ssl_preread`/ALPN split) still needs LIVE per-transport testing on a real VPS before relying on it in production.

## v1.1.0 — 2026-10-02 — Review Akhir BAGIAN A-C
### Added
- Audit kode: shellcheck 168 warnings → 0, eval 4 → 0, backtick 0
- Audit keamanan: chmod 600 untuk db/bot.conf/private key/backup, 664 → 0, Squid 127.0.0.1 deny all, bot admin-only mask 6 char
- Logrotate: /var/log/mytunnel.log + /var/log/xray/*.log + nginx daily rotate 7/14
- BAGIAN C: menu doctor (db vs Xray vs system), uninstall.sh bersih, VERSION/CHANGELOG, versi dinamis di menu

### Fixed
- build_tahap6.sh embed delimiter menempel → 6 setup files hilang (fixed echo "" before __EMBED_EOF__)
- server.csr/ca.srl 664 → 644, nginx-sim.log/sshd-sim.log 664 → 644
- xray.service.sim Restart=always RestartSec=3 (sebelum hanya on-failure)
- Idempotency: ports.conf preserve guard, keep clients Xray, cron dedup

### Security
- Flock semua DB write, backup .bak-TS + validasi xray -test/nginx -t + rollback
- Token mask, never log password/UUID

## v1.0.0 — 2026-10-01 — TAHAP 1-6+8 lengkap
- TAHAP 1: kerangka 60 kolom, lib/colors/helpers/sysinfo, menu/main
- TAHAP 2: domain/firewall/cert/xray(9 inbounds)/nginx(http2+grpc)
- TAHAP 3: SSH dropbear/sshws/autoexpire/limitip
- TAHAP 4: VMess/VLESS/Trojan proto_helpers gen_links
- TAHAP 5: 11 features (bandwidth/reboot/speedtest/services/backup/domain/banner/security/autoupdate)
- TAHAP 6: bot+warp+routing+slowdns (optional, admin-only, keep_outbounds preserve)
- TAHAP 8: SSH extra (Squid/UDPGW/OHP/OpenVPN/SlowDNS/UDP-Custom) exclusive 80/443

