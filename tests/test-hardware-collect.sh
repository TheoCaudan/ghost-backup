#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="$ROOT/compatibility/hardware/collect.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

PASS=0
FAIL=0

ok() {
    printf '[OK] %s\n' "$1"
    ((PASS += 1))
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    ((FAIL += 1))
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        ok "$label"
    else
        fail "$label (attendu: $expected, obtenu: $actual)"
    fi
}

assert_json() {
    local label="$1" query="$2" expected="$3"
    local actual

    actual="$(jq -r "$query" <<< "$JSON")"
    assert_eq "$label" "$expected" "$actual"
}

# Environnement simulé
mkdir -p "$TMP/bin" "$TMP/drm" "$TMP/net" "$TMP/bluetooth"

cat > "$TMP/bin/lscpu" <<'MOCK'
#!/usr/bin/env bash
cat <<'CPU'
Vendor ID: AuthenticAMD
Model name: AMD Ryzen Test CPU
CPU
MOCK

cat > "$TMP/bin/lspci" <<'MOCK'
#!/usr/bin/env bash
cat "$GHOST_TEST_PCI"
MOCK

cat > "$TMP/bin/lsblk" <<'MOCK'
#!/usr/bin/env bash
cat <<'DISKS'
sda disk sata
nvme0n1 disk nvme
sda1 part
DISKS
MOCK

cat > "$TMP/bin/uname" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
    -m) echo x86_64 ;;
    -r) echo 6.12.1-test ;;
    *) exit 1 ;;
esac
MOCK

chmod +x "$TMP/bin/"*

cat > "$TMP/os-release" <<'OS'
NAME="Ghost Test OS"
OS

# Faux périphériques sysfs
mkdir -p "$TMP/drm/card0-eDP-1" "$TMP/drm/card0-HDMI-A-1"
echo connected > "$TMP/drm/card0-eDP-1/status"
echo disconnected > "$TMP/drm/card0-HDMI-A-1/status"

mkdir -p "$TMP/net/wlp2s0/wireless" "$TMP/net/enp1s0" "$TMP/net/docker0"
ln -s /dev/null "$TMP/net/wlp2s0/device"
ln -s /dev/null "$TMP/net/enp1s0/device"

mkdir -p "$TMP/bluetooth/hci0"

export PATH="$TMP/bin:/usr/bin:/bin"
export GHOST_OS_RELEASE="$TMP/os-release"
export GHOST_SYS_CLASS_DRM="$TMP/drm"
export GHOST_SYS_CLASS_NET="$TMP/net"
export GHOST_SYS_CLASS_BLUETOOTH="$TMP/bluetooth"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland

# Scénario 1 : machine complète
cat > "$TMP/pci-full" <<'PCI'
0000:01:00.0 VGA compatible controller: NVIDIA Test GPU
        Kernel driver in use: nvidia
0000:02:00.0 Ethernet controller: Realtek Test Ethernet
        Kernel driver in use: r8169
0000:03:00.0 Network controller: Intel Test WiFi
        Kernel driver in use: iwlwifi
0000:04:00.0 Audio device: AMD Test Audio
        Kernel driver in use: snd_hda_intel
0000:05:00.0 USB controller: AMD Test USB
        Kernel driver in use: xhci_hcd
0000:06:00.0 Non-Volatile memory controller: Test NVMe
        Kernel driver in use: nvme
PCI

export GHOST_TEST_PCI="$TMP/pci-full"

if ! JSON="$("$COLLECTOR" --json)"; then
    fail "Collecte JSON de la machine complète"
else
    ok "Collecte JSON de la machine complète"

    if jq -e . >/dev/null <<< "$JSON"; then
        ok "JSON valide"
    else
        fail "JSON valide"
    fi

    assert_json "Version du schéma" '.schema_version' '1'
    assert_json "Distribution" '.system.distribution' 'Ghost Test OS'
    assert_json "Architecture" '.system.architecture' 'x86_64'
    assert_json "Modèle CPU" '.cpu.model' 'AMD Ryzen Test CPU'
    assert_json "GPU détecté" '.graphics | length' '1'
    assert_json "Pilote GPU" '.graphics[0].driver' 'nvidia'
    assert_json "Contrôleur Ethernet" '.network_controllers | length' '2'
    assert_json "Contrôleur audio" '.audio_controllers | length' '1'
    assert_json "Contrôleur USB" '.usb_controllers | length' '1'
    assert_json "Contrôleur stockage" '.storage_controllers | length' '1'
    assert_json "Disques" '.disks | length' '2'
    assert_json "Interface Wi-Fi" '[.network_interfaces[] | select(.type == "wifi")] | length' '1'
    assert_json "Interface virtuelle" '[.network_interfaces[] | select(.type == "virtual")] | length' '1'
    assert_json "Écrans détectés" '.monitors | length' '2'
    assert_json "Écran connecté" '[.monitors[] | select(.status == "connected")] | length' '1'
    assert_json "Bluetooth détecté" '.bluetooth.controller_count' '1'
    assert_json "Session graphique" '.session.desktop' 'Hyprland'

    if jq -e '[.. | objects | keys[]] | all(. != "serial" and . != "mac" and . != "ip" and . != "hostname")' >/dev/null <<< "$JSON"; then
        ok "Absence de champs personnels sensibles"
    else
        fail "Absence de champs personnels sensibles"
    fi
fi

# Vérification du mode humain
if HUMAN="$("$COLLECTOR" --human)" &&
   grep -q 'INVENTAIRE MATÉRIEL GHOST' <<< "$HUMAN" &&
   grep -q 'Bluetooth : 1 contrôleur' <<< "$HUMAN"; then
    ok "Mode humain"
else
    fail "Mode humain"
fi

# Scénario 2 : machine minimale
: > "$TMP/pci-empty"
export GHOST_TEST_PCI="$TMP/pci-empty"

rm -rf "$TMP/bluetooth/"*
mkdir -p "$TMP/bluetooth"

if ! JSON="$("$COLLECTOR" --json)"; then
    fail "Collecte JSON de la machine minimale"
else
    ok "Collecte JSON de la machine minimale"
    assert_json "Aucun GPU" '.graphics | length' '0'
    assert_json "Aucun contrôleur réseau" '.network_controllers | length' '0'
    assert_json "Aucun contrôleur audio" '.audio_controllers | length' '0'
    assert_json "Aucun contrôleur USB" '.usb_controllers | length' '0'
    assert_json "Aucun Bluetooth" '.bluetooth.controller_count' '0'
fi

# Argument invalide
if "$COLLECTOR" --invalid >/dev/null 2>&1; then
    fail "Rejet d'un argument invalide"
else
    status=$?
    assert_eq "Code de sortie pour argument invalide" '2' "$status"
fi

printf '\nRésultat : %s réussis / %s échoués\n' "$PASS" "$FAIL"

(( FAIL == 0 ))
