#!/usr/bin/env bash

set -Eeuo pipefail

section() {
    printf '\n\033[1;36m== %s ==\033[0m\n' "$1"
}

section "Système"

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf 'Distribution : %s\n' "${PRETTY_NAME:-inconnue}"
fi

printf 'Architecture  : %s\n' "$(uname -m)"
printf 'Noyau         : %s\n' "$(uname -r)"

section "Processeur"

if command -v lscpu >/dev/null 2>&1; then
    lscpu | grep -E '^(Model name|Architecture|CPU\(s\)|Vendor ID):' || true
else
    echo "lscpu indisponible"
fi

section "Cartes graphiques et pilotes"

if command -v lspci >/dev/null 2>&1; then
    lspci -nnk | grep -A3 -E \
        'VGA compatible controller|3D controller|Display controller' || true
else
    echo "lspci indisponible (paquet pciutils)"
fi

section "Modules graphiques chargés"

if [[ -r /proc/modules ]]; then
    grep -E '^(nvidia|amdgpu|i915|xe|nouveau) ' /proc/modules \
        | awk '{print $1}' \
        | sort -u || echo "Aucun module correspondant détecté."
fi

section "Paquets graphiques"

if command -v pacman >/dev/null 2>&1; then
    pacman -Q nvidia-open-dkms nvidia-utils mesa \
        vulkan-icd-loader linux linux-headers linux-firmware \
        2>/dev/null || true
fi

section "Outils de l'environnement"

for command in hyprctl waybar yay nvim stow starship; do
    if command -v "$command" >/dev/null 2>&1; then
        printf '[PRÉSENT] %s\n' "$command"
    else
        printf '[ABSENT]  %s\n' "$command"
    fi
done

section "Fin de l'analyse"

echo "Analyse terminée. Aucune modification du système effectuée."
