#!/usr/bin/env bash

set -Eeuo pipefail

DOTFILES_DIR="${GHOST_DOTFILES_DIR:-$HOME/src/dotfiles}"
PACMAN_MANIFEST="$DOTFILES_DIR/pacman-list.txt"
YAY_MANIFEST="$DOTFILES_DIR/yay-list.txt"

error() {
    printf '[ERROR] %s\n' "$1" >&2
}

load_manifest() {
    local file="$1"
    local target_name="$2"
    local -n target="$target_name"
    local line package extra
    local -A seen=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        package=""
        extra=""
        read -r package extra <<< "$line" || true

        [[ -z "$package" ]] && continue

        if [[ ! "$package" =~ ^[A-Za-z0-9@._+-]+$ ]] || [[ -n "$extra" ]]; then
            error "Entrée invalide dans $file : $line"
            return 1
        fi

        if [[ -z "${seen[$package]+present}" ]]; then
            target+=("$package")
            seen["$package"]=1
        fi
    done < "$file"
}

refresh_installed() {
    local output package

    if ! output="$(pacman -Qq)"; then
        error "Impossible de récupérer la liste des paquets installés."
        return 1
    fi

    installed=()

    while IFS= read -r package; do
        [[ -n "$package" ]] && installed["$package"]=1
    done <<< "$output"
}

calculate_missing() {
    local package

    missing_pacman=()
    missing_yay=()

    for package in "${pacman_packages[@]}"; do
        if [[ -z "${installed[$package]+present}" ]]; then
            missing_pacman+=("$package")
        fi
    done

    for package in "${yay_packages[@]}"; do
        if [[ -z "${installed[$package]+present}" ]]; then
            missing_yay+=("$package")
        fi
    done
}

confirm() {
    local answer

    printf '\n%s [o/N] ' "$1"
    read -r answer

    [[ "$answer" == "o" || "$answer" == "O" || "$answer" == "oui" || "$answer" == "OUI" ]]
}

show_plan() {
    local pacman_present yay_present

    pacman_present=$((${#pacman_packages[@]} - ${#missing_pacman[@]}))
    yay_present=$((${#yay_packages[@]} - ${#missing_yay[@]}))

    printf '\n===== GHOST BACKUP : PLAN D INSTALLATION =====\n'
    printf 'Mode : %s\n' "$MODE"
    printf 'Dépôt dotfiles : %s\n' "$DOTFILES_DIR"

    printf '\n--- Paquets officiels ---\n'
    printf 'Déclarés : %s | Présents : %s | À installer : %s\n' \
        "${#pacman_packages[@]}" "$pacman_present" "${#missing_pacman[@]}"

    if ((${#missing_pacman[@]})); then
        printf 'Commande prévue :\n  '
        printf '%q ' sudo pacman -S --needed -- "${missing_pacman[@]}"
        printf '\n'
    else
        printf '[OK] Tous les paquets officiels sont déjà présents.\n'
    fi

    printf '\n--- Paquets AUR ---\n'
    printf 'Déclarés : %s | Présents : %s | À installer : %s\n' \
        "${#yay_packages[@]}" "$yay_present" "${#missing_yay[@]}"

    if ((${#missing_yay[@]})); then
        if command -v yay >/dev/null 2>&1; then
            printf 'Commande prévue :\n  '
            printf '%q ' yay -S --needed -- "${missing_yay[@]}"
            printf '\n'
        else
            printf '[INFO] Yay absent : bootstrap nécessaire avant installation AUR.\n'
        fi
    else
        printf '[OK] Tous les paquets AUR sont déjà présents.\n'
    fi
}

bootstrap_yay() {
    if command -v yay >/dev/null 2>&1; then
        return 0
    fi

    if (( EUID == 0 )); then
        error "Le bootstrap de Yay doit être exécuté par un utilisateur normal."
        return 1
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo est indisponible."
        return 1
    fi

    if ! confirm "Préparer le bootstrap de Yay (base-devel, git, go) ?"; then
        printf '[INFO] Bootstrap Yay annulé.\n'
        return 1
    fi

    printf '\n[INFO] Vérification des dépendances de compilation...\n'

    sudo pacman -S --needed -- base-devel git go || {
        error "Installation des dépendances de compilation échouée."
        return 1
    }

    if ! command -v git >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
        error "git ou makepkg est indisponible."
        return 1
    fi

    printf '\n[INFO] Récupération des sources officielles de Yay...\n'

    (
        local build_dir
        local -a built_packages=()

        build_dir="$(mktemp -d "${TMPDIR:-/tmp}/ghost-yay.XXXXXX")" || exit 1
        trap 'rm -rf -- "$build_dir"' EXIT

        git clone --depth 1 https://aur.archlinux.org/yay.git "$build_dir/yay" || exit 1
        cd "$build_dir/yay" || exit 1

        printf '\n[INFO] Compilation de Yay sans privilèges root...\n'
        makepkg --noconfirm || exit 1

        mapfile -d '' -t built_packages < <(
            find . -maxdepth 1 -type f \
                -name 'yay-*.pkg.tar.*' ! -name '*.sig' -print0
        )

        if ((${#built_packages[@]} != 1)); then
            error "Nombre inattendu de paquets Yay construits : ${#built_packages[@]}"
            exit 1
        fi

        printf '\n[INFO] Paquet construit : %s\n' "${built_packages[0]}"

        if ! confirm "Installer ce paquet Yay avec Pacman ?"; then
            printf '[INFO] Installation de Yay annulée.\n'
            exit 1
        fi

        sudo pacman -U -- "${built_packages[0]}"
    ) || {
        error "Le bootstrap de Yay a échoué ou a été annulé."
        return 1
    }

    if ! command -v yay >/dev/null 2>&1; then
        error "Yay reste introuvable après son installation."
        return 1
    fi

    printf '[OK] Yay est disponible.\n'
}
apply_installation() {
    if (( EUID == 0 )); then
        error "Ne lance pas Ghost en root. Utilise ton compte normal."
        return 1
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo est indisponible."
        return 1
    fi

    if ((${#missing_pacman[@]})); then
        if confirm "Installer les ${#missing_pacman[@]} paquets officiels ?"; then
            sudo pacman -S --needed -- "${missing_pacman[@]}" || {
                error "Installation des paquets officiels échouée."
                return 1
            }
            printf '[OK] Installation officielle terminée.\n'
        else
            printf '[INFO] Installation officielle ignorée.\n'
        fi
    fi

    refresh_installed || return 1
    calculate_missing

    if ((${#missing_yay[@]})); then
        if ! bootstrap_yay; then
            error "Installation AUR impossible sans Yay."
            return 1
        fi

        if confirm "Installer les ${#missing_yay[@]} paquets AUR ?"; then
            yay -S --needed -- "${missing_yay[@]}" || {
                error "Installation des paquets AUR échouée."
                return 1
            }
            printf '[OK] Installation AUR terminée.\n'
        else
            printf '[INFO] Installation AUR ignorée.\n'
        fi
    fi

    printf '\n[OK] Opérations d installation terminées.\n'
}

main() {
    local argument="${1:---dry-run}"

    case "$argument" in
        --dry-run) MODE="SIMULATION — aucune modification" ;;
        --apply) MODE="INSTALLATION RÉELLE — confirmations requises" ;;
        *)
            printf 'Usage : %s [--dry-run|--apply]\n' "$0" >&2
            return 2
            ;;
    esac

    if [[ $# -gt 1 ]]; then
        error "Trop d'arguments."
        return 2
    fi

    if [[ "$MODE" == "INSTALLATION RÉELLE — confirmations requises" ]]; then
        if (( EUID == 0 )); then
            error "Ghost doit être lancé depuis un compte utilisateur normal."
            return 1
        fi

        if [[ ! -t 0 ]]; then
            error "Le mode --apply nécessite un terminal interactif."
            return 1
        fi
    fi

    if ! command -v pacman >/dev/null 2>&1; then
        error "pacman est introuvable. Ghost nécessite Arch Linux."
        return 1
    fi

    for file in "$PACMAN_MANIFEST" "$YAY_MANIFEST"; do
        if [[ ! -s "$file" ]]; then
            error "Manifeste absent ou vide : $file"
            return 1
        fi
    done

    local -a pacman_packages=()
    local -a yay_packages=()
    local -a missing_pacman=()
    local -a missing_yay=()

    declare -A installed=()

    load_manifest "$PACMAN_MANIFEST" pacman_packages || return 1
    load_manifest "$YAY_MANIFEST" yay_packages || return 1

    refresh_installed || return 1
    calculate_missing
    show_plan

    if [[ "$MODE" == "SIMULATION — aucune modification" ]]; then
        printf '\n[OK] Simulation terminée. Aucune installation lancée.\n'
        return 0
    fi

    apply_installation
}

main "$@"
