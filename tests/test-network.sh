#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

PASS=0
FAIL=0

pass() {
    printf '[PASS] %s\n' "$1"
    PASS=$((PASS + 1))
}

fail() {
    printf '[FAIL] %s\n' "$1"
    FAIL=$((FAIL + 1))
}

SYS_NET="$TEMP_DIR/sys/class/net"
SYS_PCI="$TEMP_DIR/sys/bus/pci/devices"
DRIVERS="$TEMP_DIR/drivers"
BIN="$TEMP_DIR/bin"
NO_RFKILL_BIN="$TEMP_DIR/no-rfkill-bin"

mkdir -p "$SYS_NET" "$SYS_PCI" "$DRIVERS" "$BIN" "$NO_RFKILL_BIN"

# Commandes simulées
cat > "$BIN/ip" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat > "$BIN/lspci" <<'MOCK'
#!/usr/bin/env bash
cat <<'PCI'
0000:02:00.0 Ethernet controller [0200]: Realtek RTL8111 [10ec:8168]
0000:03:00.0 Network controller [0280]: Realtek RTL8822CE [10ec:c822]
PCI
MOCK

cat > "$BIN/rfkill" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_RFKILL_OUTPUT:-}"
MOCK

chmod +x "$BIN"/*

# Faux pilotes
mkdir -p "$DRIVERS/r8169" "$DRIVERS/rtw88_8822ce"

# Contrôleurs PCI avec pilotes
mkdir -p "$SYS_PCI/0000:02:00.0" "$SYS_PCI/0000:03:00.0"
ln -s "$DRIVERS/r8169" "$SYS_PCI/0000:02:00.0/driver"
ln -s "$DRIVERS/rtw88_8822ce" "$SYS_PCI/0000:03:00.0/driver"

# Interfaces réseau simulées
mkdir -p "$SYS_NET/eth0/device" "$SYS_NET/wlan0/wireless" "$SYS_NET/wlan0/device" "$SYS_NET/docker0"

printf 'down\n' > "$SYS_NET/eth0/operstate"
printf '0\n' > "$SYS_NET/eth0/carrier"
printf 'up\n' > "$SYS_NET/wlan0/operstate"
printf '1\n' > "$SYS_NET/wlan0/carrier"
ln -s "$DRIVERS/r8169" "$SYS_NET/eth0/device/driver"
ln -s "$DRIVERS/rtw88_8822ce" "$SYS_NET/wlan0/device/driver"
printf 'down\n' > "$SYS_NET/docker0/operstate"

run_check() {
    PATH="$1" \
    GHOST_SYS_CLASS_NET="$SYS_NET" \
    GHOST_SYS_BUS_PCI_DEVICES="$SYS_PCI" \
    MOCK_RFKILL_OUTPUT="${2:-}" \
    /usr/bin/bash "$ROOT_DIR/compatibility/checks/network.sh" 2>&1
}

BASE_OUTPUT="$(run_check "$BIN:/usr/bin:/bin")"

if grep -q 'Pilote actif : r8169' <<< "$BASE_OUTPUT" &&
   grep -q 'Pilote actif : rtw88_8822ce' <<< "$BASE_OUTPUT" &&
   grep -q 'Interface active.' <<< "$BASE_OUTPUT"; then
    pass "Détection Ethernet, Wi-Fi et pilotes actifs"
else
    fail "Détection Ethernet, Wi-Fi et pilotes actifs"
    printf '%s\n' "$BASE_OUTPUT"
fi

if grep -q 'Aucun lien physique détecté' <<< "$BASE_OUTPUT"; then
    pass "Ethernet sans câble signalé en INFO"
else
    fail "Ethernet sans câble signalé en INFO"
fi

if grep -q 'Interface virtuelle' <<< "$BASE_OUTPUT"; then
    pass "Interface virtuelle reconnue"
else
    fail "Interface virtuelle reconnue"
fi

# Contrôleur PCI sans pilote
rm "$SYS_PCI/0000:03:00.0/driver"
NO_DRIVER_OUTPUT="$(run_check "$BIN:/usr/bin:/bin")"

if grep -q 'Aucun pilote actif détecté pour 0000:03:00.0' <<< "$NO_DRIVER_OUTPUT"; then
    pass "Contrôleur PCI sans pilote signalé"
else
    fail "Contrôleur PCI sans pilote signalé"
    printf '%s\\n' "$NO_DRIVER_OUTPUT"
    if [[ -L "$SYS_PCI/0000:03:00.0/driver" ]]; then
        printf '[DEBUG] Le lien symbolique du pilote existe encore.\\n'
    fi
fi

# Blocage Wi-Fi logiciel
RFKILL_OUTPUT=$'0: phy0: Wireless LAN\n\tSoft blocked: yes\n\tHard blocked: no\n1: hci0: Bluetooth\n\tSoft blocked: yes\n\tHard blocked: no'
BLOCKED_OUTPUT="$(run_check "$BIN:/usr/bin:/bin" "$RFKILL_OUTPUT")"

if grep -q 'Wi-Fi bloqué logiciellement' <<< "$BLOCKED_OUTPUT" &&
   ! grep -q 'Wi-Fi bloqué matériellement' <<< "$BLOCKED_OUTPUT"; then
    pass "Blocage logiciel Wi-Fi détecté"
else
    fail "Blocage logiciel Wi-Fi détecté"
fi

# Bluetooth bloqué ne doit pas être signalé comme Wi-Fi bloqué
BLUETOOTH_OUTPUT=$'0: hci0: Bluetooth\n\tSoft blocked: yes\n\tHard blocked: no'
BT_OUTPUT="$(run_check "$BIN:/usr/bin:/bin" "$BLUETOOTH_OUTPUT")"

if ! grep -q 'Wi-Fi bloqué logiciellement' <<< "$BT_OUTPUT"; then
    pass "Blocage Bluetooth ignoré par le contrôle Wi-Fi"
else
    fail "Blocage Bluetooth ignoré par le contrôle Wi-Fi"
fi

# rfkill absent
cp "$BIN/ip" "$NO_RFKILL_BIN/ip"
cp "$BIN/lspci" "$NO_RFKILL_BIN/lspci"
ln -sfn "$(command -v bash)" "$NO_RFKILL_BIN/bash"
ln -sfn "$(command -v cat)" "$NO_RFKILL_BIN/cat"
ln -sfn "$(command -v readlink)" "$NO_RFKILL_BIN/readlink"
ln -sfn "$(command -v cat)" "$NO_RFKILL_BIN/cat"
ln -sfn "$(command -v readlink)" "$NO_RFKILL_BIN/readlink"
NO_RFKILL_OUTPUT="$(run_check "$NO_RFKILL_BIN")"

if grep -q 'rfkill indisponible' <<< "$NO_RFKILL_OUTPUT"; then
    pass "Absence de rfkill gérée proprement"
else
    fail "Absence de rfkill gérée proprement"
fi

printf '\nRésultat : %d réussi(s), %d échec(s).\n' "$PASS" "$FAIL"

((FAIL == 0))
