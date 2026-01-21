#!/usr/bin/env bash
# Beacon script for PXE boot end-to-end testing.
#
# Runs inside the PXE-booted NixOS ISO after reaching multi-user.target.
# Sends an HTTP request to the router's darkhttpd (port 1337) containing
# "NIXOS-PXE-BOOT-SUCCESS". The test driver polls the router's journal
# for this string to confirm the full boot chain worked.
#
# Environment:
#   ROUTER_IP  - IP of the PXE boot server (set by systemd Environment=)
#
# Requires: curl, iproute2, networkmanager, systemd (in $PATH)

set -euo pipefail

log() { tee /dev/ttyS0; }
log_msg() { echo "$1" | log; }

log_msg "=== PXE Boot Beacon Starting ==="

# ── Network setup ──────────────────────────────────────────────────────
# Clean up auto-created NM profiles and activate all interfaces.
nmcli connection delete "Wired connection 1" 2>&1 | log || true
nmcli connection delete "Wired connection 2" 2>&1 | log || true
for dev in ens4 ens8 eth0 eth1; do
	nmcli device set "$dev" managed yes 2>&1 | log || true
done
nmcli connection up "Wired-Auto" 2>&1 | log || true
sleep 3

# ── Wait for IPv4 (up to 90s) ─────────────────────────────────────────
log_msg "Waiting for IPv4 address..."
for i in $(seq 1 90); do
	if ip -4 addr show | grep "inet " | grep -qv "127.0.0.1"; then
		log_msg "IPv4 address detected"
		break
	fi
	if [ $((i % 30)) -eq 0 ]; then
		log_msg "Still waiting ($i/90s)..."
		nmcli device status 2>&1 | log || true
	fi
	sleep 1
done

# Resolve our IP for logging (ens8 is the PXE interface in the test VM)
IP=$(nmcli -g IP4.ADDRESS device show ens8 2>/dev/null | cut -d/ -f1 | head -1)
[ -z "$IP" ] && IP=$(ip -4 addr show ens8 | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
log_msg "My IP: ${IP:-NONE}"

if [ -z "$IP" ]; then
	log_msg "ERROR: No IP, network failed"
	ip addr show | log
	exit 1
fi

# ── Send beacon ───────────────────────────────────────────────────────
TIMESTAMP=$(date +%s)
BEACON_URL="http://${ROUTER_IP}:1337/NIXOS-PXE-BOOT-SUCCESS-${TIMESTAMP}"
log_msg "Sending beacon to ${BEACON_URL}"
curl -s -m 10 "$BEACON_URL" 2>&1 | log || true

# ── Shutdown ──────────────────────────────────────────────────────────
log_msg "=== Beacon complete, shutting down ==="
sleep 3
systemctl poweroff
