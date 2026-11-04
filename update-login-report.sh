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
parts = text.split("<<'__EMBED_EOF__'")

# Map variable names to target paths
path_map = {
    '$LR_DIR/lib/common.sh': os.path.join(base, 'lib', 'common.sh'),
    '$LR_DIR/lib/collector.sh': os.path.join(base, 'lib', 'collector.sh'),
    '$LR_DIR/lib/core.sh': os.path.join(base, 'lib', 'core.sh'),
    '$LR_DIR/config.conf': os.path.join(etc, 'config.conf'),
    '$LR_DIR/menu.sh': os.path.join(base, 'menu.sh'),
    '$LR_DIR/uninstall.sh': os.path.join(base, 'uninstall.sh'),
}

# Find which block corresponds to which file by looking at the cat > line before each heredoc
extracted = {}
for i in range(1, len(parts), 2):
    if i >= len(parts):
        break
    # Get the line before this heredoc opening
    before = text[:text.find("<<'__EMBED_EOF__'", text.find(parts[i-1]) if i > 0 else 0)]
    # Find the last cat > ... line
    cat_lines = re.findall(r'cat > (\$\w+(?:/\S+)?)', before)
    if not cat_lines:
        continue
    target_var = cat_lines[-1]
    block = parts[i].split('__EMBED_EOF__')[0]
    extracted[target_var] = block

# Write files
for var, content in extracted.items():
    target = path_map.get(var)
    if not target:
        print(f"[!] Skip unknown target: {var}")
        continue
    
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, 'w') as f:
        f.write(content)
    
    # Set permissions
    if 'config.conf' in target or 'uninstall.sh' in target:
        os.chmod(target, 0o600)
    else:
        os.chmod(target, 0o755)
    
    print(f"[+] Updated: {target}")

print("[+] Selesai. Restart service:")
print("    systemctl daemon-reload && systemctl restart login-report.timer")
PYEOF

echo "[+] File login-report berhasil di-update."
echo "[+] Jalankan: systemctl daemon-reload && systemctl restart login-report.timer"
