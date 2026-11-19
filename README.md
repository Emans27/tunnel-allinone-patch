# tunnel-allinone-patch

Installer VPN tunnel all-in-one **satu file** (single-file installer). Gabungan
instalasi Xray (Vmess/Vless/Trojan), Dropbear, SSH over WebSocket (HTTP Custom
PATCH/GET), Nginx multiplexer, TLS chain 443, SlowDNS, UDP-Custom, ZiVPN, OHP,
Squid, OpenVPN, dan panel menu CLI — semuanya ter-embed di dalam `install.sh`.

## Instalasi (satu file, tanpa git clone)

```bash
apt update && apt install -y wget curl && wget -O install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone-patch/main/install.sh && chmod +x install.sh && ./install.sh
```

Interaktif (tanya domain & brand sendiri):

```bash
wget -O install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone-patch/main/install.sh && chmod +x install.sh && ./install.sh
```

Non-interaktif (langsung):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Emans27/tunnel-allinone-patch/main/install.sh)" --domain <domain> --brand "<Brand>" --yes
```

## Argumen & Environment

| Argumen | Env | Keterangan |
|---|---|---|
| `--domain` | `MYTUNNEL_DOMAIN` | domain VPS (wajib utk TLS/LE) |
| `--brand` | `MYTUNNEL_BRAND` | nama brand di menu/banner |
| `--yes` | `MYTUNNEL_YES=1` | lanjut tanpa konfirmasi |
| `--no-deps` | — | lewati instalasi paket |
| `--acme-mail` | `MYTUNNEL_ACME_EMAIL` | email Let's Encrypt |
| — | `MYTUNNEL_EXPIRY` | tanggal expiry akun trial |

## Port

Port dikonfigurasi di bagian atas `install.sh` (sebelumnya `ports.conf`, kini
di-embed). Semua port ditulis ke `/etc/mytunnel/config/ports.conf` saat install.

## Dukungan

- Ubuntu ≤ 24.04, Debian ≤ 13
- arsitektur x86_64 & arm64
- root required

## Setelah install

```bash
menu              # buka panel
mytunnel-doctor   # cek konsistensi db vs Xray vs system
bash /root/uninstall.sh   # hapus (ketik: hapus)
```

## Struktur repo

Repo ini sengaja hanya berisi 1 file installer + metadata GitHub:

```
install.sh     # SELURUH instalasi (self-contained)
README.md
LICENSE
VERSION
CHANGELOG.md
SHA256SUMS
```

Semua sub-skrip (setup, menu, fitur, cron, unit systemd, `configure-final-443`,
`ports.conf`, `verify`, `uninstall`, login-report) ter-embed di dalam
`install.sh` dan diekstrak saat runtime.
