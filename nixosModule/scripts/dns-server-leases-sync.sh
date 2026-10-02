# Triggered by dns-server-leases-reload.path watching
# $DNS_SERVER_LEASES_KEA_FILE (written by dns-server-lease-hook.sh, itself
# invoked by Kea's run_script hook). Runs as root (no User= on this
# service), unlike the Kea-spawned hook script -- which is why this half
# exists at all: kea-dhcp4-server's DynamicUser sandbox makes its whole
# state directory unreadable to the unprivileged unbound user (see
# leasesKeaStateDirectory's comment in config-dns.nix), so root has to
# copy the file out to a location unbound can actually open, then trigger
# the reload the Kea-side sandbox also can't do itself.

shared_dir="$(dirname "$DNS_SERVER_LEASES_SHARED_FILE")"
mkdir -p "$shared_dir"

# `mv` within the same directory as the destination is an atomic rename;
# `install`/`cp` directly onto the destination are not (a reader could see
# a partial write).
tmp="$(mktemp "$shared_dir/.leases.XXXXXX")"
chmod 0644 "$tmp"
cat "$DNS_SERVER_LEASES_KEA_FILE" >"$tmp"
mv "$tmp" "$DNS_SERVER_LEASES_SHARED_FILE"

systemctl reload unbound.service
