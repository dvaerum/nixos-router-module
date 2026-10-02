# Invoked by Kea's libdhcp_run_script.so hook (kea-dhcp4-server) on every
# lease commit/expiry/release. Kea passes the hook-point name as $1 and the
# lease data as environment variables (LEASE4_*, LEASES4_AT<n>_*,
# DELETED_LEASES4_AT<n>_*) -- see the Run Script hook chapter of the Kea ARM.
# All other configuration comes in via env vars set by config-dns.nix
# (DNS_SERVER_LEASES_*), since Kea only ever passes the hook-point name as
# an argument -- there's no way to add our own fixed argv.

hook_point="${1:-}"

facts_dir="$DNS_SERVER_LEASES_STATE_DIR/facts"
mkdir -p "$facts_dir"

is_allowed_subnet() {
  grep -qxF "$1" "$DNS_SERVER_ALLOWED_SUBNET_IDS_FILE"
}

is_reserved_mac() {
  printf '%s\n' "$1" | tr 'A-F' 'a-f' | grep -qxFf - "$DNS_SERVER_RESERVED_MACS_FILE"
}

is_reserved_fqdn() {
  grep -qxF "$1" "$DNS_SERVER_RESERVED_FQDNS_FILE"
}

# RPZ QNAME triggers are relative to the zone's own origin (`name:` in the
# unbound rpz: clause) -- NOT absolute names -- so strip the trailing dot
# Kea's LEASE4_HOSTNAME/LEASES4_AT<n>_HOSTNAME already qualifies it with.
strip_trailing_dot() {
  printf '%s' "${1%.}"
}

# $1 = lease address (the fact's key -- stable across renewals of the same
# lease, unlike the hostname), $2 = hwaddr, $3 = subnet id, $4 = FQDN
# hostname Kea resolved for this lease (already qualified + sanitized by
# Kea; may be empty).
publish_fact() {
  addr="$1"
  hwaddr="$2"
  subnet_id="$3"
  hostname="$(strip_trailing_dot "$4")"

  fact_file="$facts_dir/$addr"
  rm -f "$fact_file"

  if ! is_allowed_subnet "$subnet_id"; then
    return 0
  fi

  if is_reserved_mac "$hwaddr"; then
    : # a reservation's own hostname always publishes, regardless of the
      # publish-pool-leases toggle -- Kea already resolved LEASE4_HOSTNAME
      # to the reservation's hostname (it always takes precedence), so
      # there's nothing left to check here.
  elif [ "$DNS_SERVER_PUBLISH_POOL_LEASES" = "1" ]; then
    if [ -z "$hostname" ] || is_reserved_fqdn "$hostname"; then
      return 0
    fi
  else
    return 0
  fi

  [ -n "$hostname" ] || return 0
  echo "$hostname A $addr" >"$fact_file"
}

remove_fact() {
  rm -f "$facts_dir/$1"
}

# Kea's DynamicUser sandbox has no D-Bus/systemctl access, so this only
# writes the zonefile -- a separate root-owned systemd.path unit
# (dns-server-leases-reload, see config-dns.nix) watches it and does the
# actual `systemctl reload unbound.service`.
regenerate_zonefile() {
  # `sort` makes this independent of find's directory-traversal order, so
  # the same underlying facts always produce byte-identical output --
  # otherwise the serial/cmp-based idempotency check below could see a
  # "change" that's really just a reordering.
  records="$(find "$facts_dir" -type f -exec cat {} + | sort)"
  # unbound's RPZ zone has a `url:` alongside `zonefile:` (see
  # config-dns.nix, the checkconf-fatal workaround), which appears to make
  # it treat the SOA serial as a real freshness signal on reload -- a
  # serial that never changes went unnoticed on a second content update
  # in testing. Content-derived (not a timestamp) so it stays STABLE when
  # the record set is unchanged, which the idempotency check below needs.
  serial="$(printf '%s' "$records" | cksum | cut -d' ' -f1)"

  tmp_zone="$(mktemp)"
  trap 'rm -f "$tmp_zone"' EXIT

  {
    echo "\$TTL 60"
    echo "@ SOA localhost. admin.localhost. ($serial 3600 900 604800 60)"
    echo "@ NS  localhost."
    printf '%s\n' "$records"
  } >"$tmp_zone"

  if [ -e "$DNS_SERVER_LEASES_RPZ_OUT" ] && cmp -s "$tmp_zone" "$DNS_SERVER_LEASES_RPZ_OUT"; then
    return 0
  fi

  # `mv` within the same directory as the destination is an atomic rename;
  # `install`/`cp` are not (a reader could see a partial write).
  final_tmp="$(mktemp "$(dirname "$DNS_SERVER_LEASES_RPZ_OUT")/.leases.XXXXXX")"
  chmod 0644 "$final_tmp"
  cat "$tmp_zone" >"$final_tmp"
  mv "$final_tmp" "$DNS_SERVER_LEASES_RPZ_OUT"
}

case "$hook_point" in
leases4_committed)
  changed=0
  size="${LEASES4_SIZE:-0}"
  i=0
  while [ "$i" -lt "$size" ]; do
    addr_var="LEASES4_AT${i}_ADDRESS"
    hwaddr_var="LEASES4_AT${i}_HWADDR"
    subnet_var="LEASES4_AT${i}_SUBNET_ID"
    hostname_var="LEASES4_AT${i}_HOSTNAME"
    publish_fact "${!addr_var:-}" "${!hwaddr_var:-}" "${!subnet_var:-}" "${!hostname_var:-}"
    changed=1
    i=$((i + 1))
  done

  deleted_size="${DELETED_LEASES4_SIZE:-0}"
  i=0
  while [ "$i" -lt "$deleted_size" ]; do
    addr_var="DELETED_LEASES4_AT${i}_ADDRESS"
    remove_fact "${!addr_var:-}"
    changed=1
    i=$((i + 1))
  done

  [ "$changed" = "1" ] && regenerate_zonefile
  ;;

lease4_expire)
  if [ "${REMOVE_LEASE:-}" = "true" ] || [ "${REMOVE_LEASE:-}" = "1" ]; then
    remove_fact "$LEASE4_ADDRESS"
    regenerate_zonefile
  fi
  ;;

lease4_release)
  remove_fact "$LEASE4_ADDRESS"
  regenerate_zonefile
  ;;

*)
  # Other hook points (lease4_renew, lease4_recover, lease4_decline, ...)
  # are intentionally not handled: `leases4_committed` already covers new
  # AND renewed leases, so there's nothing further to publish for them.
  ;;
esac
