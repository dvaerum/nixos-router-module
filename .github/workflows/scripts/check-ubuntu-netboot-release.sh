#!/usr/bin/env bash
# Checks whether a newer Ubuntu LTS netboot release is available than the
# one currently pinned in packages/pxe-boot-grub-signed/package.nix, and if
# so, bumps the version + hashes in place.
#
# Exits 0 either way; signals the result via $GITHUB_OUTPUT (bumped=true/false,
# new_version=<version>) so the calling workflow can decide whether to open a
# PR. Never pushes or opens a PR itself -- that's the workflow's job, so a
# build-verification step can run on the bumped tree first.
set -euo pipefail

PACKAGE_NIX="${PACKAGE_NIX:-packages/pxe-boot-grub-signed/package.nix}"

current_version=$(grep -oP '(?<=version = ")[^"]+(?=";)' "$PACKAGE_NIX" | head -1)
echo "Current pinned version: $current_version"

# Only ".04" directories are LTS releases -- the only ones that ship the
# netboot tarball this package needs. Both ".04" (alias to latest point
# release) and ".04.N" (concrete point release) directories can appear;
# the HEAD-request existence check below naturally prefers whichever
# actually has a matching tarball filename, no special-casing needed.
mapfile -t candidates < <(
  curl -fsSL https://releases.ubuntu.com/ \
    | grep -oP '(?<=href=")[0-9]+\.04(\.[0-9]+)?(?=/")' \
    | sort -V -u
)

latest_valid=""
for v in "${candidates[@]}"; do
  amd64_url="https://releases.ubuntu.com/${v}/ubuntu-${v}-netboot-amd64.tar.gz"
  arm64_url="https://cdimage.ubuntu.com/releases/${v}/release/ubuntu-${v}-netboot-arm64.tar.gz"
  if curl -fsSL --head "$amd64_url" >/dev/null 2>&1 \
     && curl -fsSL --head "$arm64_url" >/dev/null 2>&1; then
    latest_valid="$v"
  fi
done

if [ -z "$latest_valid" ]; then
  echo "No Ubuntu LTS release with both amd64 and arm64 netboot tarballs found -- nothing to do."
  echo "bumped=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

echo "Latest release with both netboot tarballs present: $latest_valid"

if [ "$latest_valid" = "$current_version" ]; then
  echo "Already up to date."
  echo "bumped=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

# Guard against a withdrawn/yanked release reordering things unexpectedly,
# or a malformed version string sorting in a surprising place: only ever
# bump forward.
if ! printf '%s\n%s\n' "$current_version" "$latest_valid" | sort -V -C; then
  echo "Discovered version $latest_valid is not newer than pinned $current_version -- skipping."
  echo "bumped=false" >>"$GITHUB_OUTPUT"
  exit 0
fi

echo "Bumping $current_version -> $latest_valid"

amd64_sha256=$(nix-prefetch-url --type sha256 "https://releases.ubuntu.com/${latest_valid}/ubuntu-${latest_valid}-netboot-amd64.tar.gz" 2>/dev/null | tail -1)
amd64_sri=$(nix hash convert --to sri --hash-algo sha256 "$amd64_sha256")

arm64_sha256=$(nix-prefetch-url --type sha256 "https://cdimage.ubuntu.com/releases/${latest_valid}/release/ubuntu-${latest_valid}-netboot-arm64.tar.gz" 2>/dev/null | tail -1)
arm64_sri=$(nix hash convert --to sri --hash-algo sha256 "$arm64_sha256")

sed -i "s/version = \"${current_version}\";/version = \"${latest_valid}\";/" "$PACKAGE_NIX"

# Replace the two `hash = "...";` fields in file order (amd64 fetchurl
# block comes first, arm64 second). A single-pass awk counter is used
# instead of two separate seds: after the first sed rewrites occurrence
# 1, a second "replace the first remaining match" sed would just re-match
# that SAME already-rewritten line again, not reach occurrence 2.
awk -v amd64="$amd64_sri" -v arm64="$arm64_sri" '
  /hash = "/ {
    n++
    if (n == 1) { sub(/hash = "[^"]*";/, "hash = \"" amd64 "\";") }
    else if (n == 2) { sub(/hash = "[^"]*";/, "hash = \"" arm64 "\";") }
  }
  { print }
' "$PACKAGE_NIX" >"${PACKAGE_NIX}.tmp"
mv "${PACKAGE_NIX}.tmp" "$PACKAGE_NIX"

echo "bumped=true" >>"$GITHUB_OUTPUT"
echo "new_version=${latest_valid}" >>"$GITHUB_OUTPUT"
