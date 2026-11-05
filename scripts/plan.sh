#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES_DIR="${GHOST_DOTFILES_DIR:-$HOME/src/dotfiles}"
PACMAN_MANIFEST="$DOTFILES_DIR/pacman-list.txt"
YAY_MANIFEST="$DOTFILES_DIR/yay-list.txt"

ok()      { printf '[OK]          %s\n' "$1"; }
info()    { printf '[INFO]        %s\n' "$1"; }
warning() { printf '[À INSTALLER] %s\n' "$1"; }
error()   { printf '[ERREUR]      %s\n' "$1" >&2; }

printf '\n===== GHOST BACKUP : PLAN DES PAQUETS =====\n'
printf 'Manifestes : %s\n' "$DOTFILES_DIR"

if ! command -v pacman >/dev/null 2>&1; then
    error "pacman est introuvable."
    exit 1
fi

if [[ ! -r "$PACMAN_MANIFEST" ]]; then
    error "Manifeste absent ou illisible : $PACMAN_MANIFEST"
    exit 1
fi

if [[ ! -r "$YAY_MANIFEST" ]]; then
    error "Manifeste absent ou illisible : $YAY_MANIFEST"
    exit 1
fi

mapfile -t PACMAN_PACKAGES < <(
    sed 's/#.*//' "$PACMAN_MANIFEST" | awk 'NF { print $1 }'
)

mapfile -t YAY_PACKAGES < <(
    sed 's/#.*//' "$YAY_MANIFEST" | awk 'NF { print $1 }'
)

if ! INSTALLED_OUTPUT="$(pacman -Qq)"; then
    error "Impossible de récupérer la liste des paquets installés."
    exit 1
fi

declare -A INSTALLED=()

while IFS= read -r package; do
    [[ -n "$package" ]] && INSTALLED["$package"]=1
done <<< "$INSTALLED_OUTPUT"

PACMAN_OK=0
PACMAN_MISSING=0
YAY_OK=0
YAY_MISSING=0

printf '\n--- Paquets des dépôts officiels ---\n'

for package in "${PACMAN_PACKAGES[@]}"; do
    if [[ ${INSTALLED[$package]+present} ]]; then
        ok "$package"
        ((PACMAN_OK += 1))
    else
        warning "$package"
        ((PACMAN_MISSING += 1))
    fi
done

printf '\n--- Paquets AUR ---\n'

for package in "${YAY_PACKAGES[@]}"; do
    if [[ ${INSTALLED[$package]+present} ]]; then
        ok "$package"
        ((YAY_OK += 1))
    else
        warning "$package"
        ((YAY_MISSING += 1))
    fi
done

printf '\n===== RÉSUMÉ =====\n'
printf 'Pacman : %d présents, %d manquants\n' \
    "$PACMAN_OK" "$PACMAN_MISSING"
printf 'AUR    : %d présents, %d manquants\n' \
    "$YAY_OK" "$YAY_MISSING"

if (( YAY_MISSING > 0 )); then
    if command -v yay >/dev/null 2>&1; then
        ok "yay disponible pour les futurs paquets AUR."
    else
        warning "yay absent : prérequis nécessaire pour les futurs paquets AUR."
    fi
fi

printf '\nAucune modification du système effectuée.\n'
