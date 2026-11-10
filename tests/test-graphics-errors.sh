#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPHICS_SCRIPT="$ROOT/compatibility/checks/graphics.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

PASS=0
FAIL=0
OUT=""
STATUS=0

ok() {
    printf '[OK] %s\n' "$1"
    ((PASS += 1))
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    ((FAIL += 1))
}

check() {
    local label="$1"
    shift

    if "$@"; then
        ok "$label"
    else
        fail "$label"
        printf '  --- sortie (code %s) ---\n%s\n' "$STATUS" "$OUT" >&2
    fi
}

status_is() { (( STATUS == $1 )); }
out_has()   { grep -Fq -- "$1" <<< "$OUT"; }

mkdir -p "$TMP/bin" "$TMP/nolspci" "$TMP/dotfiles/config/hypr/configs"

# Faux lspci : un GPU NVIDIA.
cat > "$TMP/bin/lspci" <<'MOCK'
#!/usr/bin/env bash
cat <<'PCI'
01:00.0 3D controller [0302]: NVIDIA Corporation GPU [10de:25ad]
    Kernel driver in use: nvidia
PCI
MOCK

# Faux hyprctl : pas de session active.
cat > "$TMP/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK

chmod +x "$TMP/bin/"*

# PATH minimal sans lspci : seulement les outils utilisés par graphics.sh.
for tool in env bash awk sed grep head cat; do
    ln -sf "$(command -v "$tool")" "$TMP/nolspci/$tool"
done

# run_graphics <PATH>
run_graphics() {
    if OUT="$(PATH="$1" GHOST_DOTFILES_DIR="$TMP/dotfiles" \
        "$GRAPHICS_SCRIPT" 2>&1)"; then
        STATUS=0
    else
        STATUS=$?
    fi
}

# 1. monitors.lua référencé mais absent : erreur, code 1
printf 'require("configs.monitors")\n' > "$TMP/dotfiles/config/hypr/hyprland.lua"
rm -f "$TMP/dotfiles/config/hypr/configs/monitors.lua"
run_graphics "$TMP/bin:$PATH"
check "module monitors absent : code de sortie 1" status_is 1
check "module monitors absent : erreur affichée"  out_has 'monitors.lua référencé mais absent'

# 2. monitors.lua référencé et présent : succès, code 0
printf 'hl.monitor({ output = "eDP-1" })\n' > "$TMP/dotfiles/config/hypr/configs/monitors.lua"
run_graphics "$TMP/bin:$PATH"
check "module monitors présent : code de sortie 0" status_is 0

# 3. lspci absent du PATH : erreur, code 1
run_graphics "$TMP/nolspci"
check "lspci absent : code de sortie 1" status_is 1
check "lspci absent : erreur affichée"  out_has 'lspci absent'

printf '\nRésultat : %s réussis / %s échoués\n' "$PASS" "$FAIL"

(( FAIL == 0 ))
