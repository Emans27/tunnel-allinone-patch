# MyTunnel — TUNNEL PRO v1.9.10

Tunneling All-In-One untuk **Debian 11/12 + Ubuntu 18/20/22/24**. Xray VMess/VLess/Trojan (WS, gRPC, HTTPUpgrade) + SSH/Dropbear/OpenSSH, Nginx 443 exclusive.

## Install

**Domain WAJIB diisi.** Install tanpa domain akan gagal (bug terdokumentasi, lihat bawah).
Sekali paste, di VPS **root** — ganti `domain.kamu` dengan domain Anda:

```bash
wget -qO install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone/main/install.sh \
  && MYTUNNEL_DOMAIN=domain.kamu MYTUNNEL_BRAND="SUNEK VPN" MYTUNNEL_YES=1 bash install.sh
```

**Syarat sebelum install:**
- A-record domain → IP VPS (cek: `dig +short A domain.kamu` hasilnya = IP VPS)
- Cloudflare proxy **OFF** (awan abu, bukan oranye)
- Port 80/443/444/81/8443 kosong
- Masih bisa login SSH port 22 setelah install (dropbear pindah ke :90, OpenSSH ke :444)

**Setelah selesai:**

```bash
ss -tlnp | grep -E ':(80|443|8443|444|90)\b'
menu
```

### Kenapa domain wajib?

Dua bug installer terpicu kalau domain kosong (Enter saja / `MYTUNNEL_DOMAIN` tak diisi):

1. **Install mati diam-diam setelah `Arch: x86_64 ✓`** — baris
   `MYTUNNEL_DOMAIN="${MYTUNNEL_DOMAIN:-$(cat /etc/mytunnel/domain.txt 2>/dev/null)}"`
   gagal karena `/etc/mytunnel/domain.txt` belum ada, dan `set -e` menghentikan installer
   tanpa pesan. Gejala: prompt balik ke shell, tidak ada tahap `[1/13]`.
2. **Kalau dipaksa lanjut** (file domain.txt dibuat manual berisi `-`): `xray.service`
   gagal start (`/var/log/xray` permission denied, ownership `nobody:nogroup`),
   nginx `mytunnel.conf` tidak dibuat (guard `die "Domain belum diisi"`), WS 502.

Domain yang sudah terlanjur salah pasang bisa diganti lewat
**menu → 6 FEATURES → 9 Change Domain VPS** (issue cert Let's Encrypt ulang,
rollback otomatis kalau gagal). Tapi install pertama tetap harus pakai domain.

## Menu

| Menu | Isi |
|---|---|
| 1 SSH | Create / Trial / Renew / Delete / Check |
| 2-4 VMess / VLESS / Trojan | Create / Trial / Renew / Delete / Check |
| 5 SETUP BOT | Token bot + admin chat ID |
| 6 FEATURES | Backup, Domain, Banner, Security, Auto-Update, Sysinfo, layanan tambahan |
| 7 SET REDUCE/TIME | Timezone, reduce |
| 8 SET BRAND NAME | Read-only (brand permanen) |
| 9 CHECK SERVICES | Status xray / nginx / ssh / dropbear |
| 10 LOGIN REPORT | Laporan user aktif ke Telegram |

Bot dan LOGIN REPORT perlu token dari @BotFather dulu. Config-nya mode 600.

## Port

| Layanan | Port |
|---|---|
| OpenSSH / Dropbear | 444 / 90 |
| TLS / None TLS / Any | 443,8443 / 80,8080 / 2082,2083,8880 |
| Config | 81 |

Ubah angka di `/etc/mytunnel/config/ports.conf`, bukan di script.

## Arsitektur 443

```
443 -> nginx stream ssl_preread
      ALPN h2/http1.1 -> nginx 127.0.0.1:9443
      ALPN lain        -> stunnel 127.0.0.1:4443
8443 -> nginx TLS/http2
80   -> httpmux
```

Dijalankan otomatis saat install. Manual kalau perlu:

```bash
bash /root/configure-final-443.sh --dry-run
bash /root/configure-final-443.sh
```

## Update / Uninstall

```bash
menu -> 6 FEATURES -> Auto Update
bash uninstall.sh --backup
```

## Troubleshooting

| Gejala | Cek |
|---|---|
| Sertifikat gagal | `dig +short A domain` == `curl -4 ifconfig.me`; `bash /etc/mytunnel/setup/cert.sh --force` |
| 443 tidak listen | `bash /root/configure-final-443.sh` |
| Xray tidak start | `xray run -test -c /usr/local/etc/xray/config.json`; cek `stat -c '%U:%G' /var/log/xray` harus `xray:xray` |
| Tidak konek | `curl -v https://DOMAIN/vmess`; `ufw status`; `systemctl status xray nginx` |
| Token bot ditolak | `cat /etc/login-report/config.conf`, pastikan `BOT_TOKEN` + `CHAT_ID` terisi |

```bash
mytunnel-doctor
tail -n 100 /var/log/mytunnel.log
```

## Lisensi

MIT — `SHA256SUMS` 12 entri, `sha256sum -c SHA256SUMS` harus `12/12 OK`.

Sebelum commit, aktifkan guard secret + cek checksum (sekali per clone):

```bash
git config core.hooksPath .githooks
```

> Pakai hanya di VPS milik sendiri. Penulis tidak bertanggung jawab atas sanksi provider.
