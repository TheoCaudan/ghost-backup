#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/scripts/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

PASS=0
FAIL=0
OUT=""
STATUS=0

ok() {
    printf '[OK] %s\n' "$1"
    ((PASS += 1))
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    ((FAIL += 1))
}

# check <libellé> <commande...> : OK si la commande réussit, sinon affiche
# la sortie du script testé et le journal des appels pour comprendre.
check() {
    local label="$1"
    shift

    if "$@"; then
        ok "$label"
    else
        fail "$label"
        printf '  --- sortie ---\n%s\n  --- appels ---\n' "$OUT" >&2
        cat "$GHOST_TEST_LOG" >&2
    fi
}

# Prédicats utilisés avec check
status_is()      { (( STATUS == $1 )); }
status_nonzero() { (( STATUS != 0 )); }
out_has()        { grep -Fq -- "$1" <<< "$OUT"; }

# Seuls « pacman -Qq » et « pacman -Sp ... » (lectures) sont autorisés.
no_mutation() {
    ! grep -Ev '^pacman (-Qq$|-Sp )' "$GHOST_TEST_LOG" | grep -q .
}

# Environnement simulé
mkdir -p "$TMP/bin" "$TMP/dotfiles"
export GHOST_TEST_LOG="$TMP/calls.log"
export GHOST_TEST_INSTALLED="$TMP/installed"
export GHOST_DOTFILES_DIR="$TMP/dotfiles"

# Faux outils : ils journalisent chaque appel et ne modifient rien.
for cmd in sudo yay makepkg git; do
    cat > "$TMP/bin/$cmd" <<'MOCK'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$GHOST_TEST_LOG"
MOCK
done

# Faux pacman : -Qq liste les paquets installés, -Sp peut échouer à la demande.
cat > "$TMP/bin/pacman" <<'MOCK'
#!/usr/bin/env bash
echo "pacman $*" >> "$GHOST_TEST_LOG"

case "${1:-}" in
    -Qq)
        cat "$GHOST_TEST_INSTALLED"
        ;;
    -Sp)
        if [[ -n "${GHOST_TEST_SP_FAIL:-}" ]]; then
            echo "error: target not found: ${GHOST_TEST_SP_FAIL}" >&2
            exit 1
        fi
        ;;
esac

exit 0
MOCK

# Faux pacman-conf : multilib activé, sauf si GHOST_TEST_NO_MULTILIB est défini.
cat > "$TMP/bin/pacman-conf" <<'MOCK'
#!/usr/bin/env bash
echo core
echo extra
[[ -n "${GHOST_TEST_NO_MULTILIB:-}" ]] || echo multilib
MOCK

chmod +x "$TMP/bin/"*

export PATH="$TMP/bin:/usr/bin:/bin"

reset_state() {
    : > "$GHOST_TEST_LOG"
    unset GHOST_TEST_SP_FAIL GHOST_TEST_NO_MULTILIB
    printf 'git\n' > "$GHOST_TEST_INSTALLED"
    printf 'git\nfoo\nfoo\n' > "$TMP/dotfiles/pacman-list.txt"
    printf 'bar-aur\n' > "$TMP/dotfiles/yay-list.txt"
}

# Lance l'installateur sans terminal (stdin = /dev/null) et remplit OUT/STATUS.
run_installer() {
    if OUT="$("$INSTALLER" "$@" 2>&1 < /dev/null)"; then
        STATUS=0
    else
        STATUS=$?
    fi
}

# 1. --dry-run explicite
reset_state
run_installer --dry-run
check "dry-run : code de sortie 0"                status_is 0
check "dry-run : aucune commande modifiante"      no_mutation
check "dry-run : doublon retiré, manquant détecté (pacman)" \
      out_has 'Déclarés : 2 | Présents : 1 | À installer : 1'
check "dry-run : manquant détecté (AUR)" \
      out_has 'Déclarés : 1 | Présents : 0 | À installer : 1'
check "dry-run : cibles pacman validées" \
      out_has 'Toutes les cibles pacman sont résolues'

# 2. Sans argument, c'est le dry-run
reset_state
run_installer
check "sans argument : code de sortie 0"          status_is 0
check "sans argument : aucune modification"       no_mutation

# 3. Argument invalide
reset_state
run_installer --nimportequoi
check "argument invalide : code 2"                status_is 2
check "argument invalide : aucune modification"   no_mutation

# 4. Ligne de manifeste invalide (deux jetons)
reset_state
printf 'foo bar\n' > "$TMP/dotfiles/pacman-list.txt"
run_installer --dry-run
check "manifeste invalide : refusé"               status_nonzero
check "manifeste invalide : aucune modification"  no_mutation

# 5. Manifeste vide
reset_state
: > "$TMP/dotfiles/yay-list.txt"
run_installer --dry-run
check "manifeste vide : refusé"                   status_nonzero

# 6. --apply sans terminal interactif
reset_state
run_installer --apply
check "--apply sans terminal : refusé"            status_nonzero
check "--apply sans terminal : aucune modification" no_mutation

# 7. Cible introuvable (paquet renommé ou multilib désactivé)
reset_state
export GHOST_TEST_SP_FAIL=steam
run_installer --dry-run
check "cible introuvable : code de sortie 1"      status_is 1
check "cible introuvable : erreur affichée"       out_has 'target not found: steam'
check "cible introuvable : aucune modification"   no_mutation

# 8. multilib désactivé : avertissement
reset_state
export GHOST_TEST_NO_MULTILIB=1
run_installer --dry-run
check "multilib désactivé : avertissement"        out_has 'Dépôt multilib désactivé'
check "multilib désactivé : aucune modification"  no_mutation

printf '\nRésultat : %s réussis / %s échoués\n' "$PASS" "$FAIL"

(( FAIL == 0 ))
