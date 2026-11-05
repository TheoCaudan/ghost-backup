
#!/usr/bin/env bash

set -Eeuo pipefail

GHOST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GRAPHICS_SCRIPT="$GHOST_DIR/compatibility/checks/graphics.sh"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0

# Remplace lspci par une version simulée pour le test.
create_fake_lspci() {
    cat > "$TEMP_DIR/lspci" <<'FAKE'
#!/usr/bin/env bash
cat "$FAKE_LSPCI_OUTPUT"
FAKE
    chmod +x "$TEMP_DIR/lspci"
}

create_fake_hyprctl() {
    cat > "$TEMP_DIR/hyprctl" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
    chmod +x "$TEMP_DIR/hyprctl"
}

run_test() {
    local name="$1"
    local expected="$2"
    local output

    if output="$(PATH="$TEMP_DIR:$PATH" \
        FAKE_LSPCI_OUTPUT="$TEMP_DIR/pci-output" \
        GHOST_DOTFILES_DIR="$TEMP_DIR/dotfiles" \
        "$GRAPHICS_SCRIPT" 2>&1)"; then
        :
    else
        printf '[ÉCHEC] %s : le script a retourné une erreur.\n' "$name"
        printf '%s\n' "$output"
        ((FAIL+=1))
        return
    fi

    if grep -Fq "$expected" <<< "$output"; then
        printf '[OK] %s\n' "$name"
        ((PASS+=1))
    else
        printf '[ÉCHEC] %s\n' "$name"
        printf 'Résultat attendu : %s\n' "$expected"
        printf '%s\n' "$output"
        ((FAIL+=1))
    fi
}

create_fake_lspci
create_fake_hyprctl

mkdir -p "$TEMP_DIR/dotfiles/config/hypr/configs"

cat > "$TEMP_DIR/dotfiles/config/hypr/hyprland.lua" <<'EOF'
require("configs.monitors")
EOF

cat > "$TEMP_DIR/dotfiles/config/hypr/configs/monitors.lua" <<'EOF'
hl.monitor({ output = "eDP-1" })
EOF

# Hyprland est simulé comme indisponible.
export PATH="$TEMP_DIR:$PATH"


# NVIDIA seul
cat > "$TEMP_DIR/pci-output" <<'EOF'
01:00.0 3D controller [0302]: NVIDIA Corporation GPU [10de:25ad]
    Kernel driver in use: nvidia
EOF
run_test "NVIDIA seul" "GPU NVIDIA : pilote nvidia actif."

# AMD seul
cat > "$TEMP_DIR/pci-output" <<'EOF'
06:00.0 VGA compatible controller [0300]: AMD Radeon [1002:1638]
    Kernel driver in use: amdgpu
EOF
run_test "AMD seul" "GPU AMD : pilote amdgpu actif."

# Intel seul
cat > "$TEMP_DIR/pci-output" <<'EOF'
00:02.0 VGA compatible controller [0300]: Intel Graphics [8086:1234]
    Kernel driver in use: i915
EOF
run_test "Intel seul" "Aucun GPU NVIDIA détecté."

# AMD + NVIDIA
cat > "$TEMP_DIR/pci-output" <<'EOF'
01:00.0 3D controller [0302]: NVIDIA Corporation GPU [10de:25ad]
    Kernel driver in use: nvidia
06:00.0 VGA compatible controller [0300]: AMD Radeon [1002:1638]
    Kernel driver in use: amdgpu
EOF
run_test "Hybride AMD + NVIDIA" "GPU AMD : pilote amdgpu actif."

# Aucun GPU
cat > "$TEMP_DIR/pci-output" <<'EOF'
00:14.0 USB controller [0c03]: AMD USB Controller [1022:7908]
    Kernel driver in use: xhci_hcd
EOF
run_test "Sans GPU" "Aucun GPU NVIDIA détecté."

# Audio AMD et NVIDIA sans contrôleur graphique
cat > "$TEMP_DIR/pci-output" <<'EOF'
01:00.1 Audio device [0403]: NVIDIA Audio [10de:2291]
    Kernel driver in use: snd_hda_intel
06:00.1 Audio device [0403]: AMD Audio [1002:1637]
    Kernel driver in use: snd_hda_intel
EOF
run_test "Contrôleurs audio seuls" "Aucun GPU AMD détecté."

printf '\n===== RÉSULTAT DES TESTS =====\n'
printf 'Réussis : %s\n' "$PASS"
printf 'Échoués : %s\n' "$FAIL"

if (( FAIL > 0 )); then
    exit 1
fi

printf 'Tous les tests sont réussis.\n'
