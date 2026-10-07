#!/usr/bin/env bash
# Beacon script for PXE boot end-to-end testing.
#
# Runs inside the PXE-booted NixOS ISO after reaching multi-user.target.
# Sends an HTTP request to the router's nginx vhost (port 1337) containing
# "NIXOS-PXE-BOOT-SUCCESS". The test driver polls the router's journal
# for this string to confirm the full boot chain worked.
#
# Environment:
#   ROUTER_IP  - IP of the PXE boot server (set by systemd Environment=)
#   HTTP_PORT  - port nginx listens on (set by systemd Environment=)
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
# Hardcoded interface-name lists (ens4/ens8/eth0/eth1) are not reliable here:
# predictable-network-interface-naming output depends on the kernel/systemd
# version and the PCI bus layout the VM backend assigns the NICs, both of
# which can (and did, across a nixpkgs bump) change what the PXE interface
# ends up named -- e.g. "enp0s3"/"enp0s4" instead of any of those guesses.
# Just set every present non-loopback device managed instead of guessing names.
for dev in $(ip -o link show | awk -F': ' '$2 != "lo" {print $2}'); do
	nmcli device set "$dev" managed yes 2>&1 | log || true
done
nmcli connection up "Wired-Auto" 2>&1 | log || true
sleep 3

# ── Wait for a real (non-loopback, non-link-local) IPv4 address ───────
# Same naming-instability reasoning as above: don't hardcode a device
# name, discover whichever non-loopback interface actually carries an
# address. Excluding 169.254.0.0/16 (link-local/APIPA) specifically
# matters: a self-assigned fallback address would otherwise satisfy a
# weaker "any non-127.0.0.1 address" check before DHCP actually completes.
#
# Capture `ip`'s full output into a variable FIRST, then parse it with
# plain string pipes (`printf ... | awk ...`), rather than piping `ip`
# directly into `awk '{...; exit}'`: an early `exit` inside awk's
# action closes its end of the pipe while the upstream producer may still
# be writing, which can SIGPIPE it -- under `pipefail` that non-zero exit
# propagates as the whole pipeline's status, and `set -e` would then kill
# the script with no error printed (reproduced directly: piping a 100k-line
# producer into `awk '{print; exit}'` exits 141/SIGPIPE under pipefail).
# Parsing an already-captured string sidesteps this entirely, since there's
# no live upstream producer left to SIGPIPE.
log_msg "Waiting for a real (non-link-local) IPv4 address..."
IFACE=""
IP=""
for i in $(seq 1 90); do
	RAW=$(ip -4 -o addr show 2>&1) || true
	IFACE=$(printf '%s\n' "$RAW" | awk '$4 !~ /^(127\.|169\.254\.)/ {print $2; exit}') || true
	if [ -n "$IFACE" ]; then
		IP=$(printf '%s\n' "$RAW" | awk -v d="$IFACE" '$2==d {print $4; exit}' | cut -d/ -f1) || true
		[ -n "$IP" ] && break
	fi
	if [ $((i % 30)) -eq 0 ]; then
		log_msg "Still waiting ($i/90s)..."
		nmcli device status 2>&1 | log || true
	fi
	sleep 1
done
log_msg "My interface: ${IFACE:-NONE}, IP: ${IP:-NONE}"

if [ -z "$IP" ]; then
	log_msg "ERROR: No IP, network failed"
	ip addr show | log
	exit 1
fi

# ── Send beacon ───────────────────────────────────────────────────────
TIMESTAMP=$(date +%s)
BEACON_URL="http://${ROUTER_IP}:${HTTP_PORT}/NIXOS-PXE-BOOT-SUCCESS-${TIMESTAMP}"
log_msg "Sending beacon to ${BEACON_URL} via ${IFACE}"
# `--interface "$IFACE"` is NOT redundant here: these test VMs have a
# second NIC (the nixosTest framework's own management interface) on the
# SAME /24 subnet as the PXE interface. With two routes to the same
# destination differing only by metric, the kernel's source-address/route
# selection for a new outgoing connection isn't guaranteed to prefer the
# lower-metric one -- confirmed directly: the beacon request arrived at
# the router from the OTHER interface's address, not $IP, even though $IP
# is the one with the lower metric. Binding to the discovered interface
# explicitly makes the source address match what the test expects (it
# looks up the PXE interface's own MAC in the router's ARP table to know
# which source IP to wait for).
curl -s -m 10 --interface "$IFACE" "$BEACON_URL" 2>&1 | log || true

# ── Shutdown ──────────────────────────────────────────────────────────
log_msg "=== Beacon complete, shutting down ==="
sleep 3
systemctl poweroff
