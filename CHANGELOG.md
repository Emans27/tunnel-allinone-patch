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

