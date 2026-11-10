#!/usr/bin/env bash

set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

failed=()

for test in test-*.sh; do
    printf '\n===== %s =====\n' "$test"

    if ! bash "./$test"; then
        failed+=("$test")
    fi
done

printf '\n===== BILAN DES TESTS =====\n'

if ((${#failed[@]} > 0)); then
    printf '[FAIL] Tests en échec :\n'
    printf '  - %s\n' "${failed[@]}"
    exit 1
fi

printf '[OK] Tous les fichiers de test ont réussi.\n'
