#!/bin/bash
# update-login-report.sh — patch login-report tanpa rebuild installer
set -euo pipefail

BASE="${LR_BASE:-/opt/login-report}"
ETC="${LR_ETC:-/etc/login-report}"
INSTALLER="${1:-install.sh}"

[ -f "$INSTALLER" ] || { echo "ERROR: $INSTALLER tidak ditemukan"; exit 1; }

echo "[+] Mengekstrak login-report dari $INSTALLER ..."

# Extract embedded heredocs for login-report (6 blocks: common, collector, core, config, menu, uninstall)
python3 - <<'PYEOF' "$INSTALLER" "$BASE" "$ETC"
import re, sys, os

installer = sys.argv[1]
base = sys.argv[2]
etc = sys.argv[3]

with open(installer) as f:
    text = f.read()

# Split by login-report heredoc markers
# Pattern: cat > "$VAR" <<'__EMBED_EOF__' ... __EMBED_EOF__
HEREDOC_RE = re.compile(r"<< *'__EMBED_EOF__'")

# Map variable names to target paths
path_map = {
    '$LR_DIR/lib/common.sh': os.path.join(base, 'lib', 'common.sh'),
    '$LR_DIR/lib/collector.sh': os.path.join(base, 'lib', 'collector.sh'),
    '$LR_DIR/lib/core.sh': os.path.join(base, 'lib', 'core.sh'),
    '$LR_DIR/config.conf': os.path.join(etc, 'config.conf'),
    '$LR_DIR/menu.sh': os.path.join(base, 'menu.sh'),
    '$LR_DIR/uninstall.sh': os.path.join(base, 'uninstall.sh'),
}

# Walk every heredoc opener; nearest `cat > "..."` before it names the target.
extracted = {}
openers = list(HEREDOC_RE.finditer(text))
for n, m in enumerate(openers):
    content_start = m.end()
    content_end = openers[n + 1].start() if n + 1 < len(openers) else len(text)
    closing = text.find('__EMBED_EOF__', content_start, content_end)
    if closing == -1:
        continue
    block = text[content_start:closing]
    block = block.rsplit('\n', 1)[0] if block.endswith('\n') else block
    cat_lines = re.findall(r'cat > "([^"]+)"', text[:m.start()])
    if not cat_lines:
        continue
    extracted[cat_lines[-1]] = block

# Write files
written = 0
for var, content in extracted.items():
    target = path_map.get(var)
    if not target:
        # bukan blok login-report (installer menanam banyak file lain) — abaikan
        if var.startswith('$LR'):
            print(f"[!] Skip target login-report tak dikenal: {var}")
        continue
    
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, 'w') as f:
        f.write(content)
    
    # Set permissions
    if 'config.conf' in target:
        os.chmod(target, 0o600)
    else:
        os.chmod(target, 0o755)
    
    written += 1
    print(f"[+] Updated: {target}")

expected = len(path_map)
if written != expected:
    print(f"ERROR: hanya {written}/{expected} file login-report ter-extract dari {installer}", file=sys.stderr)
    sys.exit(1)
print("[+] Selesai. Restart service:")
print("    systemctl daemon-reload && systemctl restart login-report.timer")
PYEOF

echo "[+] File login-report berhasil di-update."
echo "[+] Jalankan: systemctl daemon-reload && systemctl restart login-report.timer"
