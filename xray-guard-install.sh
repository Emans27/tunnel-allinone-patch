#!/bin/bash
# mytunnel - pasang xray watchdog di VPS yang SUDAH terinstall (tanpa install ulang)
# Jalankan sebagai root: bash xray-guard-install.sh
set -e
ETC=/etc/mytunnel
[ "$(id -u)" = "0" ] || { echo "Jalankan sebagai root"; exit 1; }
[ -d "$ETC" ] || { echo "$ETC tidak ada - mytunnel belum terinstall?"; exit 1; }

cat > "$ETC/setup/xray-guard.sh" << 'GUARD_EOF'
#!/bin/bash
# mytunnel xray-guard - dipanggil systemd timer tiap 60s. Diam bila xray sehat.
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
CFG="${BASE}/usr/local/etc/xray/config.json"
[ -n "$BASE" ] && exit 0   # test mode: no-op
XRAY_BIN=$(command -v xray 2>/dev/null || true)
[ -n "$XRAY_BIN" ] || XRAY_BIN=/usr/local/bin/xray
[ -x "$XRAY_BIN" ] || exit 0
_log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] xray-guard: $1" >> "$LOG" 2>/dev/null || true; }
systemctl is-active --quiet xray && exit 0
_log "xray TIDAK aktif - investigasi"
# 1) config rusak? cari backup valid terbaru
if [ -f "$CFG" ] && ! "$XRAY_BIN" run -test -config "$CFG" >/dev/null 2>&1; then
  _log "config.json tidak valid - cari backup valid"
  for b in $(ls -t "$CFG".bak-* 2>/dev/null | head -10); do
    if "$XRAY_BIN" run -test -config "$b" >/dev/null 2>&1; then
      cp -a "$CFG" "$CFG.broken-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
      cp -a "$b" "$CFG" 2>/dev/null || true
      chmod 644 "$CFG" 2>/dev/null || true
      chown nobody:nogroup "$CFG" 2>/dev/null || true
      _log "config rusak -> restore dari $b"
      break
    fi
  done
fi
# 2) restart (jaring pengaman di atas Restart=always systemd)
if systemctl restart xray >/dev/null 2>&1; then
  sleep 2
  if systemctl is-active --quiet xray; then
    _log "xray direstart, aktif kembali"
    exit 0
  fi
fi
_log "GAGAL menghidupkan xray - cek: journalctl -u xray -n 50"
exit 1
GUARD_EOF
chmod 755 "$ETC/setup/xray-guard.sh"

cat > /etc/systemd/system/mytunnel-xray-guard.service << 'SVCEOF'

Description=mytunnel Xray watchdog (restore config rusak + restart)
After=xray.service

[Service]
Type=oneshot
ExecStart=/etc/mytunnel/setup/xray-guard.sh
SVCEOF

cat > /etc/systemd/system/mytunnel-xray-guard.timer << 'TMREOF'

Description=mytunnel Xray watchdog timer (60s)

[Timer]
OnBootSec=45
OnUnitActiveSec=60
AccuracySec=5s


WantedBy=timers.target
TMREOF

chmod 644 /etc/systemd/system/mytunnel-xray-guard.service /etc/systemd/system/mytunnel-xray-guard.timer
systemctl daemon-reload
systemctl enable --now mytunnel-xray-guard.timer
echo "OK - watchdog aktif:"
systemctl list-timers mytunnel-xray-guard.timer --no-pager | head -3
