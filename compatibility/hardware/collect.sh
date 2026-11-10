#!/usr/bin/env bash

set -Eeuo pipefail

MODE="${1:---human}"

case "$MODE" in
    --human|--json) ;;
    *)
        printf 'Usage : %s [--human|--json]\n' "$0" >&2
        exit 2
        ;;
esac

for cmd in jq lspci lscpu lsblk uname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf '[ERROR] Commande requise absente : %s\n' "$cmd" >&2
        exit 1
    fi
done

# Toutes les données sont collectées en lecture seule.
# Aucun identifiant personnel (MAC, IP, série, hostname) n'est conservé.

# Chemins configurables pour les tests, valeurs réelles par défaut.
GHOST_OS_RELEASE="${GHOST_OS_RELEASE:-/etc/os-release}"
GHOST_SYS_CLASS_DRM="${GHOST_SYS_CLASS_DRM:-/sys/class/drm}"
GHOST_SYS_CLASS_NET="${GHOST_SYS_CLASS_NET:-/sys/class/net}"
GHOST_SYS_CLASS_BLUETOOTH="${GHOST_SYS_CLASS_BLUETOOTH:-/sys/class/bluetooth}"

tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT

lscpu > "$tmpdir/cpu"
lspci -Dnnk > "$tmpdir/pci"

os_name="inconnu"
if [[ -r "$GHOST_OS_RELEASE" ]]; then
    # shellcheck source=/dev/null
    . "$GHOST_OS_RELEASE"
    os_name="${NAME:-inconnu}"
fi

cpu_vendor="$(awk -F: '/Vendor ID:/ {
    sub(/^[[:space:]]+/, "", $2); print $2; exit
}' "$tmpdir/cpu")"

cpu_model="$(awk -F: '/Model name:/ {
    sub(/^[[:space:]]+/, "", $2); print $2; exit
}' "$tmpdir/cpu")"

cpu_arch="$(uname -m)"
kernel="$(uname -r)"

# Convertit les périphériques PCI en objets JSON.
# Chaque périphérique commence par une adresse PCI, sans séparateur vide.
pci_json() {
    local pattern="$1"

    awk -v pattern="$pattern" '
        function emit() {
            if (selected && slot != "") {
                printf "%s\t%s\t%s\n", slot, name, driver
            }
        }

        /^[[:xdigit:]:.]+ / {
            emit()

            slot = $1
            name = $0
            sub(/^[^ ]+ /, "", name)
            driver = ""
            selected = ($0 ~ pattern)
            next
        }

        selected && /Kernel driver in use:/ {
            driver = $0
            sub(/^.*Kernel driver in use: /, "", driver)
        }

        END {
            emit()
        }
    ' "$tmpdir/pci" |
    jq -Rn '
        [inputs | split("\t") | {
            pci_address: .[0],
            model: .[1],
            driver: .[2]
        }]
    '
}

graphics_json="$(pci_json 'VGA compatible controller|3D controller|Display controller')"
network_json="$(pci_json 'Ethernet controller|Network controller')"
audio_json="$(pci_json 'Audio device')"
multimedia_json="$(pci_json 'Multimedia controller')"
usb_json="$(pci_json 'USB controller')"
storage_json="$(pci_json 'Non-Volatile memory controller|SATA controller|RAID bus controller')"

# Écrans : aucun identifiant EDID ni numéro de série.
monitors_json="$(
    for screen in "$GHOST_SYS_CLASS_DRM"/card*-*; do
        [[ -f "$screen/status" ]] || continue
        connector="${screen##*/}"
        status="$(cat "$screen/status")"
        printf '%s\t%s\n' "$connector" "$status"
    done | jq -Rn '
        [inputs | split("\t") | {
            connector: .[0],
            status: .[1]
        }]
    '
)"

# Interfaces réseau : noms et types uniquement, jamais MAC/IP.
interfaces_json="$(
    for iface in "$GHOST_SYS_CLASS_NET"/*; do
        [[ -e "$iface" ]] || continue
        name="${iface##*/}"
        [[ "$name" == "lo" ]] && continue

        type="physical"
        [[ -d "$iface/wireless" ]] && type="wifi"
        [[ -L "$iface/device" ]] || type="virtual"

        printf '%s\t%s\n' "$name" "$type"
    done | jq -Rn '
        [inputs | split("\t") | {
            name: .[0],
            type: .[1]
        }]
    '
)"

bluetooth_count=0

for controller in "$GHOST_SYS_CLASS_BLUETOOTH"/*; do
  [[ -e "$controller" ]] || continue
  ((bluetooth_count += 1))
done

# Inventaire des périphériques de stockage sans UUID, labels ou séries.
disks_json="$(
    lsblk -dn -o NAME,TYPE,TRAN |
    awk '$2 == "disk" { printf "%s\t%s\n", $1, $3 }' |
    jq -Rn '
        [inputs | split("\t") | {
            name: .[0],
            transport: (.[1] // "")
        }]
    '
)"

session_type="${XDG_SESSION_TYPE:-unknown}"
desktop="${XDG_CURRENT_DESKTOP:-unknown}"

jq -n \
    --arg os "$os_name" \
    --arg architecture "$cpu_arch" \
    --arg kernel "$kernel" \
    --arg cpu_vendor "$cpu_vendor" \
    --arg cpu_model "$cpu_model" \
    --arg session "$session_type" \
    --arg desktop "$desktop" \
    --argjson graphics "$graphics_json" \
    --argjson network "$network_json" \
    --argjson audio "$audio_json" \
    --argjson multimedia "$multimedia_json" \
    --argjson usb "$usb_json" \
    --argjson storage_controllers "$storage_json" \
    --argjson monitors "$monitors_json" \
    --argjson interfaces "$interfaces_json" \
    --argjson disks "$disks_json" \
    --argjson bluetooth_count "$bluetooth_count" \
    '{
        schema_version: 1,
        system: {
            distribution: $os,
            architecture: $architecture,
            kernel: $kernel
        },
        cpu: {
            vendor: $cpu_vendor,
            model: $cpu_model
        },
        graphics: $graphics,
        network_controllers: $network,
        audio_controllers: $audio,
        multimedia_controllers: $multimedia,
        usb_controllers: $usb,
        storage_controllers: $storage_controllers,
        disks: $disks,
        network_interfaces: $interfaces,
        monitors: $monitors,
        bluetooth: {
            controller_count: $bluetooth_count
        },
        session: {
            type: $session,
            desktop: $desktop
        }
    }' > "$tmpdir/inventory.json"

if [[ "$MODE" == "--json" ]]; then
    cat "$tmpdir/inventory.json"
else
    jq -r '
        "===== INVENTAIRE MATÉRIEL GHOST =====",
        "Système : \(.system.distribution) / \(.system.architecture)",
        "Noyau : \(.system.kernel)",
        "CPU : \(.cpu.model)",
        "",
        "GPU :",
        (.graphics[]? | "  - \(.model) [\(.driver)]"),
        "",
        "Réseau :",
        (.network_controllers[]? | "  - \(.model) [\(.driver)]"),
        "",
        "Audio :",
        (.audio_controllers[]? | "  - \(.model) [\(.driver)]"),
        "",
        "Écrans :",
        (.monitors[]? | "  - \(.connector) : \(.status)"),
        "",
        "Stockage :",
        (.disks[]? | "  - \(.name) [\(.transport)]"),
        "",
        "Bluetooth : \(.bluetooth.controller_count) contrôleur(s)",
        "Session : \(.session.type) / \(.session.desktop)"
    ' "$tmpdir/inventory.json"
fi
