if [ "$#" -lt 2 ]; then
  echo "usage: $0 <output-rpz-file> <url> [url...]" >&2
  exit 1
fi

output="$1"
shift

# Boilerplate every hosts-file list includes (localhost, broadcasthost, the
# IPv6 loopback aliases, ...) -- not real ad/tracker domains, so they're
# dropped rather than turned into pointless RPZ rules.
exclude_regex='^(localhost|localhost\.localdomain|local|broadcasthost|ip6-localhost|ip6-loopback|ip6-localnet|ip6-mcastprefix|ip6-allnodes|ip6-allrouters|ip6-allhosts|0\.0\.0\.0)$'

tmp_domains="$(mktemp)"
tmp_zone="$(mktemp)"
trap 'rm -f "$tmp_domains" "$tmp_zone"' EXIT

for url in "$@"; do
  echo "dns-server-blocklist-update: fetching $url" >&2
  curl --fail --silent --show-error --location "$url"
  echo
done |
  awk '
    /^[[:space:]]*#/ { next }
    NF == 1 { print $1; next }
    NF >= 2 && ($1 == "0.0.0.0" || $1 == "127.0.0.1") { print $2 }
  ' |
  tr -d '\r' |
  grep -Ev "$exclude_regex" |
  sort -u \
    >"$tmp_domains"

domain_count="$(wc -l <"$tmp_domains")"
echo "dns-server-blocklist-update: $domain_count domains" >&2

# unbound's RPZ zone has a `url:` alongside `zonefile:` (see config-dns.nix,
# the checkconf-fatal workaround), which appears to make it treat the SOA
# serial as a real freshness signal on reload -- a fixed serial risks going
# unnoticed on a content-changing reload. Content-derived (not a
# timestamp) so it stays STABLE when the domain set is unchanged, which
# the idempotency check below relies on.
serial="$(cksum <"$tmp_domains" | cut -d' ' -f1)"

{
  echo "\$TTL 60"
  echo "@ SOA localhost. admin.localhost. ($serial 3600 900 604800 60)"
  echo "@ NS  localhost."
  # RPZ QNAME triggers are relative to the zone's own origin (`name:` in
  # the unbound rpz: clause) -- NOT absolute names -- so no trailing dot.
  awk '{ print $0 " CNAME ." }' "$tmp_domains"
} >"$tmp_zone"

if [ -e "$output" ] && cmp -s "$tmp_zone" "$output"; then
  echo "dns-server-blocklist-update: unchanged, skipping reload" >&2
  exit 0
fi

# `install` copies rather than renames, so a reader could see a partial
# write; `mv` within the same directory as `$output` is an atomic rename.
final_tmp="$(mktemp "$(dirname "$output")/.blocklist.XXXXXX")"
chmod 0644 "$final_tmp"
cat "$tmp_zone" >"$final_tmp"
mv "$final_tmp" "$output"
systemctl reload unbound.service
