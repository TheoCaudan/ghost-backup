#!/usr/bin/env bash

set -Eeuo pipefail

GHOST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CHECK_SCRIPT="$GHOST_DIR/compatibility/check.sh"
GRAPHICS_SCRIPT="$GHOST_DIR/compatibility/checks/graphics.sh"
COMMANDS_SCRIPT="$GHOST_DIR/compatibility/checks/commands.sh"

usage() {
    cat <<'USAGE'
Ghost Backup

Usage:
  ./ghost.sh check    Analyse la machine et les configurations
  ./ghost.sh plan     Affiche l'état actuel du projet
  ./ghost.sh verify   Vérifie les prérequis
  ./ghost.sh install [--dry-run|--apply]  Prépare ou exécute le plan
  ./ghost.sh help     Affiche cette aide
USAGE
}

check_prerequisites() {
    local errors=0
    local warnings=0
    local dotfiles_dir="${GHOST_DOTFILES_DIR:-$HOME/src/dotfiles}"

    printf '%s\n' "--- Commandes indispensables ---"

    for command in bash pacman uname git; do
        if command -v "$command" >/dev/null 2>&1; then
            printf '[OK] %s\n' "$command"
        else
            printf '[ERROR] Commande absente : %s\n' "$command"
            ((errors += 1))
        fi
    done

    printf '\n%s\n' "--- Outils complémentaires ---"

    if command -v yay >/dev/null 2>&1; then
        printf '[OK] yay\n'
    else
        printf '[WARNING] yay absent : installation AUR indisponible.\n'
        ((warnings += 1))
    fi

    if command -v lspci >/dev/null 2>&1; then
        printf '[OK] lspci\n'
    else
        printf '[INFO] lspci absent (paquet pciutils).\n'
    fi

    printf '\n%s\n' "--- Répertoires ---"

    if [[ -d "$GHOST_DIR/.git" ]]; then
        printf '[OK] Dépôt Ghost : %s\n' "$GHOST_DIR"
    else
        printf '[WARNING] Dépôt Git Ghost introuvable.\n'
        ((warnings += 1))
    fi

    if [[ -d "$dotfiles_dir/.git" ]]; then
        printf '[OK] Dépôt dotfiles : %s\n' "$dotfiles_dir"
    else
        printf '[ERROR] Dépôt dotfiles introuvable : %s\n' "$dotfiles_dir"
        ((errors += 1))
    fi

    printf '\n%s\n' "--- Manifestes ---"

    for file in "$dotfiles_dir/pacman-list.txt" "$dotfiles_dir/yay-list.txt"; do
        if [[ -s "$file" ]]; then
            printf '[OK] %s\n' "$file"
        else
            printf '[ERROR] Manifeste absent ou vide : %s\n' "$file"
            ((errors += 1))
        fi
    done

    printf '\n%s\n' "--- Scripts Ghost ---"

    for file in \
        "$CHECK_SCRIPT" \
        "$GRAPHICS_SCRIPT" \
        "$COMMANDS_SCRIPT" \
        "$GHOST_DIR/scripts/plan.sh"
    do
        if [[ -x "$file" ]]; then
            printf '[OK] %s\n' "$file"
        else
            printf '[ERROR] Script absent ou non exécutable : %s\n' "$file"
            ((errors += 1))
        fi
    done

    printf '\n===== RÉSUMÉ VERIFY =====\n'
    printf 'Erreurs    : %s\n' "$errors"
    printf 'Warnings   : %s\n' "$warnings"

    if (( errors > 0 )); then
        printf '[ERROR] Vérification échouée.\n'
        return 1
    fi

    printf '[OK] Prérequis vérifiés.\n'
    return 0
}

run_checks() {
    local script
    local passed=0
    local failed=0

    printf '\n===== GHOST BACKUP : CONTRÔLES =====\n'

    for script in \
        "$CHECK_SCRIPT" \
        "$GRAPHICS_SCRIPT" \
        "$COMMANDS_SCRIPT"
    do
        printf '\n--- %s ---\n' "${script#"$GHOST_DIR"/}"

        if [[ ! -x "$script" ]]; then
            printf '[ERROR] Script absent ou non exécutable.\n'
            ((failed += 1))
            continue
        fi

        if "$script"; then
            ((passed += 1))
        else
            printf '[ERROR] Le contrôle a échoué : %s\n' "$script"
            ((failed += 1))
        fi
    done

    printf '\n===== RÉSUMÉ CHECK =====\n'
    printf 'Contrôles réussis : %s\n' "$passed"
    printf 'Contrôles échoués : %s\n' "$failed"

    if (( failed > 0 )); then
        printf '[ERROR] Certains contrôles nécessitent une attention.\n'
        return 1
    fi

    printf '[OK] Tous les contrôles sont terminés avec succès.\n'
    return 0
}

main() {
    local action="${1:-help}"

    case "$action" in
        check)
            run_checks
            ;;
        plan)
            PLAN_SCRIPT="$GHOST_DIR/scripts/plan.sh"

            if [[ ! -x "$PLAN_SCRIPT" ]]; then
                printf '[ERREUR] Script de plan absent ou non exécutable : %s\n' "$PLAN_SCRIPT" >&2
                exit 1
            fi

            "$PLAN_SCRIPT"
            ;;
        verify)
            printf 'Vérification des prérequis :\n\n'
            check_prerequisites
            ;;
        install)
            INSTALL_SCRIPT="$GHOST_DIR/scripts/install.sh"

            if [[ ! -x "$INSTALL_SCRIPT" ]]; then
                printf '[ERROR] Moteur d’installation absent ou non exécutable.\n' >&2
                exit 1
            fi

            local install_mode="${2:---dry-run}"

            if [[ $# -gt 2 ]] || [[ "$install_mode" != "--dry-run" && "$install_mode" != "--apply" ]]; then
                printf 'Usage : ./ghost.sh install [--dry-run|--apply]\n' >&2
                exit 2
            fi

            "$INSTALL_SCRIPT" "$install_mode"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            printf '[ERREUR] Commande inconnue : %s\n\n' "$action" >&2
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
