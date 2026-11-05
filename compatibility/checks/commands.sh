#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES_DIR="${GHOST_DOTFILES_DIR:-$HOME/src/dotfiles}"
HYPR_DIR="$DOTFILES_DIR/config/hypr"
MAIN_CONFIG="$HYPR_DIR/hyprland.lua"
EXEC_CONFIG="$HYPR_DIR/configs/exec.lua"
KEYBIND_CONFIG="$HYPR_DIR/configs/keybinds.lua"

ok()      { printf '[OK]      %s\n' "$1"; }
info()    { printf '[INFO]    %s\n' "$1"; }
warning() { printf '[WARNING] %s\n' "$1"; }
error()   { printf '[ERROR]   %s\n' "$1"; }

missing=0

printf '\n===== CONTRÔLE DES COMMANDES HYPRLAND =====\n'

if [[ ! -f "$MAIN_CONFIG" ]]; then
    error "Configuration principale absente : $MAIN_CONFIG"
    exit 1
fi

check_config() {
    local module="$1"
    local file="$2"

    if ! grep -Fq "require(\"$module\")" "$MAIN_CONFIG"; then
        info "$module n'est pas référencé : contrôle ignoré."
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        error "$module est référencé mais son fichier est absent."
        missing=1
        return 1
    fi

    ok "$module est référencé et son fichier existe."
    return 0
}

EXEC_ACTIVE=0
KEYBIND_ACTIVE=0

if check_config "configs.exec" "$EXEC_CONFIG"; then
    EXEC_ACTIVE=1
fi

if check_config "configs.keybinds" "$KEYBIND_CONFIG"; then
    KEYBIND_ACTIVE=1
fi

check_command() {
    local name="$1"

    if command -v "$name" >/dev/null 2>&1; then
        ok "$name disponible."
    else
        warning "$name est absent."
        missing=1
    fi
}

check_path() {
    local path="$1"

    if [[ -x "$path" ]]; then
        ok "$path disponible."
    else
        warning "$path absent ou non exécutable."
        missing=1
    fi
}

if (( EXEC_ACTIVE )); then
    printf '\n--- Dépendances de exec.lua ---\n'

    for name in \
        pkill \
        dbus-update-activation-environment \
        systemctl \
        wl-paste \
        cliphist \
        dunst \
        hyprpaper \
        nm-applet \
        lxsession \
        udiskie \
        foot \
        hyprctl
    do
        check_command "$name"
    done

    printf '\n--- Chemins absolus de exec.lua ---\n'
    check_path "/usr/bin/waybar"
    check_path "/usr/lib/polkit-kde-authentication-agent-1"
fi

if (( KEYBIND_ACTIVE )); then
    printf '\n--- Dépendances de keybinds.lua ---\n'

    for name in cliphist wofi wl-copy; do
        check_command "$name"
    done
fi

printf '\n===== FIN DU CONTRÔLE DES COMMANDES =====\n'

if (( missing )); then
    warning "Certaines dépendances sont absentes ou incomplètes."
    exit 1
fi

ok "Toutes les dépendances déclarées sont disponibles."
printf 'Aucune modification du système effectuée.\n'
