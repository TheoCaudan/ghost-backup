#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES_DIR="${GHOST_DOTFILES_DIR:-$HOME/src/dotfiles}"
HYPR_DIR="$DOTFILES_DIR/config/hypr"
MAIN_CONFIG="$HYPR_DIR/hyprland.lua"
MONITOR_CONFIG="$HYPR_DIR/configs/monitors.lua"

ERRORS=0
ok()      { printf '[OK]      %s\n' "$1"; }
info()    { printf '[INFO]    %s\n' "$1"; }
warning() { printf '[WARNING] %s\n' "$1"; }
error()   { printf '[ERROR]   %s\n' "$1"; ((ERRORS += 1)); }

printf '\n===== CONTRÔLE GRAPHIQUE =====\n'

if ! command -v lspci >/dev/null 2>&1; then
    error "lspci absent : impossible de détecter les GPU."
    exit 1
fi

# Analyse uniquement les contrôleurs VGA, 3D et Display.
GPU_INFO="$(lspci -nnk | awk '
    index($1, ":") && index($1, ".") {
        if (is_gpu) printf "%s\n\n", block

        block = $0
        is_gpu = ($0 ~ /(VGA compatible controller|3D controller|Display controller)/)
        next
    }
    {
        if (is_gpu) block = block "\n" $0
    }
    END {
        if (is_gpu) printf "%s\n\n", block
    }
')"

HAS_NVIDIA=0
HAS_AMD=0
NVIDIA_DRIVERS=()
AMD_DRIVERS=()

while IFS= read -r -d '' gpu; do
    vendor=""

    if grep -qi '10de:' <<< "$gpu"; then
        vendor="NVIDIA"
        HAS_NVIDIA=1
    elif grep -qi '1002:' <<< "$gpu"; then
        vendor="AMD"
        HAS_AMD=1
    else
        vendor="AUTRE"
    fi

    driver="$(sed -n 's/^[[:space:]]*Kernel driver in use: //p' <<< "$gpu" | head -n 1)"

    case "$vendor" in
        NVIDIA) NVIDIA_DRIVERS+=("${driver:-aucun identifié}") ;;
        AMD)    AMD_DRIVERS+=("${driver:-aucun identifié}") ;;
    esac

    printf '[DÉTECTÉ] %s : %s\n' "$vendor" "$(head -n 1 <<< "$gpu")"
done < <(printf '%s\n' "$GPU_INFO" | awk 'BEGIN { RS=""; ORS="\0" } NF')

printf '\n--- GPU et pilotes ---\n'

if (( HAS_NVIDIA )); then
    for driver in "${NVIDIA_DRIVERS[@]}"; do
        if [[ "$driver" == "nvidia" ]]; then
            ok "GPU NVIDIA : pilote nvidia actif."
        else
            warning "GPU NVIDIA : pilote actif ${driver}."
        fi
    done
else
    info "Aucun GPU NVIDIA détecté."
fi

if (( HAS_AMD )); then
    for driver in "${AMD_DRIVERS[@]}"; do
        if [[ "$driver" == "amdgpu" ]]; then
            ok "GPU AMD : pilote amdgpu actif."
        else
            warning "GPU AMD : pilote actif ${driver}."
        fi
    done
else
    info "Aucun GPU AMD détecté."
fi

printf '\n--- Configuration Hyprland ---\n'

if [[ ! -f "$MAIN_CONFIG" ]]; then
    warning "Configuration principale introuvable : $MAIN_CONFIG"
else
    ok "Configuration Lua principale trouvée."

    if grep -Fq 'require("configs.monitors")' "$MAIN_CONFIG"; then
        if [[ -f "$MONITOR_CONFIG" ]]; then
            ok "Module monitors.lua référencé et présent."
        else
            error "Module monitors.lua référencé mais absent."
        fi
    else
        info "Module monitors non référencé : contrôle des écrans indicatif."
    fi

    NVIDIA_ENV_FOUND=0

    for variable in LIBVA_DRIVER_NAME GBM_BACKEND __GLX_VENDOR_LIBRARY_NAME; do
        if grep -Fq "hl.env(\"$variable\"" "$MAIN_CONFIG"; then
            printf '  Variable NVIDIA : %s\n' "$variable"
            NVIDIA_ENV_FOUND=1
        else
            info "Variable non déclarée : $variable"
        fi
    done

    if (( NVIDIA_ENV_FOUND && ! HAS_NVIDIA )); then
        warning "Variables NVIDIA présentes, mais aucun GPU NVIDIA détecté."
    elif (( NVIDIA_ENV_FOUND && HAS_NVIDIA )); then
        ok "Configuration NVIDIA présente et GPU NVIDIA détecté."
    elif (( HAS_NVIDIA )); then
        info "GPU NVIDIA présent, aucune variable NVIDIA ciblée."
    fi
fi

printf '\n--- Écrans configurés ---\n'

if [[ ! -f "$MONITOR_CONFIG" ]]; then
    info "Fichier monitors.lua introuvable : comparaison impossible."
elif ! command -v hyprctl >/dev/null 2>&1; then
    info "hyprctl absent : écrans connectés non vérifiables."
else
    mapfile -t CONFIGURED_OUTPUTS < <(
        sed -nE 's/.*output[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$MONITOR_CONFIG"
    )

    MONITOR_REPORT="$(hyprctl monitors 2>/dev/null || true)"

    if [[ -z "$MONITOR_REPORT" ]]; then
        info "Hyprland ne fournit pas de liste d'écrans active."
    else
        mapfile -t CONNECTED_OUTPUTS < <(
            sed -nE 's/^Monitor ([^ ]+) .*/\1/p' <<< "$MONITOR_REPORT"
        )

        if (( ${#CONFIGURED_OUTPUTS[@]} == 0 )); then
            info "Aucune sortie écran reconnue dans monitors.lua."
        else
            for output in "${CONFIGURED_OUTPUTS[@]}"; do
                if printf '%s\n' "${CONNECTED_OUTPUTS[@]}" | grep -Fxq "$output"; then
                    ok "Écran configuré et connecté : $output"
                else
                    info "Écran configuré mais non connecté actuellement : $output"
                fi
            done
        fi
    fi
fi

printf '\n===== FIN DU CONTRÔLE GRAPHIQUE =====\n'
printf 'Aucune modification effectuée.\n'

if (( ERRORS > 0 )); then
    printf '[ERROR]   %s erreur(s) détectée(s).\n' "$ERRORS"
    exit 1
fi
