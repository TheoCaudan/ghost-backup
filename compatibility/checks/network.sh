#!/usr/bin/env bash

set -uo pipefail

GHOST_SYS_CLASS_NET="${GHOST_SYS_CLASS_NET:-/sys/class/net}"
GHOST_SYS_BUS_PCI_DEVICES="${GHOST_SYS_BUS_PCI_DEVICES:-/sys/bus/pci/devices}"

section() {
    printf '\n--- %s ---\n' "$1"
}

info() {
    printf '[INFO]    %s\n' "$1"
}

ok() {
    printf '[OK]      %s\n' "$1"
}

warning() {
    printf '[WARNING] %s\n' "$1"
}

section "CONTRÔLE RÉSEAU"

if ! command -v ip >/dev/null 2>&1; then
    printf '[ERROR] Commande ip indisponible (paquet iproute2).\n'
    exit 1
fi

if ! command -v lspci >/dev/null 2>&1; then
    info "lspci indisponible : détection PCI détaillée limitée."
fi

declare -A PCI_DEVICES=()

if command -v lspci >/dev/null 2>&1; then
    while IFS= read -r line; do
        [[ "$line" =~ ^([0-9a-fA-F:.]+)[[:space:]] ]] || continue
        pci_id="${BASH_REMATCH[1]}"

        if [[ "$line" =~ Ethernet\ controller|Network\ controller ]]; then
            PCI_DEVICES["$pci_id"]="$line"
        fi
    done < <(lspci -D -nn)
fi

section "CONTRÔLEURS PHYSIQUES PCI"

if ((${#PCI_DEVICES[@]} == 0)); then
    info "Aucun contrôleur réseau PCI détecté."
else
    for pci_id in "${!PCI_DEVICES[@]}"; do
        printf '%s\n' "${PCI_DEVICES[$pci_id]}"

        driver_path="$GHOST_SYS_BUS_PCI_DEVICES/$pci_id/driver"
        driver=""
        if [[ -e "$driver_path" ]]; then
            driver="$(readlink -f "$driver_path" 2>/dev/null || true)"
        fi

        if [[ -n "$driver" ]]; then
            ok "Pilote actif : ${driver##*/}"
        else
            warning "Aucun pilote actif détecté pour $pci_id."
        fi
    done
fi

section "INTERFACES RÉSEAU"

interfaces_found=0

for path in "$GHOST_SYS_CLASS_NET"/*; do
    [[ -e "$path" ]] || continue

    interface="${path##*/}"
    [[ "$interface" == "lo" ]] && continue

    interfaces_found=$((interfaces_found + 1))

    if [[ -d "$path/wireless" ]]; then
        type="Wi-Fi"
    elif [[ -d "$path/device" ]]; then
        type="Ethernet ou autre interface physique"
    else
        type="Interface virtuelle"
    fi

    state="$(cat "$path/operstate" 2>/dev/null || printf 'inconnu')"
    carrier="$(cat "$path/carrier" 2>/dev/null || true)"

    printf '\n%s : %s\n' "$interface" "$type"

    case "$state" in
        up)
            ok "Interface active."
            ;;
        down)
            info "Interface inactive."
            ;;
        dormant)
            info "Interface en attente de connexion."
            ;;
        *)
            info "État : $state."
            ;;
    esac

    if [[ "$type" == "Ethernet ou autre interface physique" ]]; then
        if [[ "$carrier" == "1" ]]; then
            ok "Lien physique connecté."
        elif [[ "$carrier" == "0" ]]; then
            info "Aucun lien physique détecté (câble débranché ou équipement indisponible)."
        fi
    fi

    driver=""
    if [[ -e "$path/device/driver" ]]; then
        driver="$(readlink -f "$path/device/driver" 2>/dev/null || true)"
    fi

    if [[ -n "$driver" ]]; then
        ok "Pilote : ${driver##*/}"
    fi

done

if ((interfaces_found == 0)); then
    info "Aucune interface réseau hors loopback détectée."
fi

section "BLOCAGES WI-FI"

if command -v rfkill >/dev/null 2>&1; then
    rfkill_output="$(rfkill list 2>/dev/null || true)"
    radio_type=""

    while IFS= read -r line; do
        if [[ "$line" =~ :[[:space:]].*Wireless[[:space:]]LAN ]]; then
            radio_type="wifi"
        elif [[ "$line" =~ :[[:space:]].*Bluetooth ]]; then
            radio_type="bluetooth"
        elif [[ "$line" =~ ^[0-9]+: ]]; then
            radio_type=""
        fi

        [[ "$radio_type" == "wifi" ]] || continue

        case "$line" in
            *"Soft blocked: yes"*)
                info "Wi-Fi bloqué logiciellement."
                ;;
            *"Hard blocked: yes"*)
                warning "Wi-Fi bloqué matériellement."
                ;;
        esac
    done <<< "$rfkill_output"
else
    info "rfkill indisponible : état du blocage Wi-Fi non vérifié."
fi

section "FIN DU CONTRÔLE RÉSEAU"
printf 'Analyse terminée. Aucune modification effectuée.\n'
