#!/usr/bin/env bash
# Unit tests for check-ubuntu-netboot-release.sh.
#
# Runs the REAL script (not a reimplementation) against a fixture
# package.nix, with `curl`/`nix-prefetch-url`/`nix` stubbed out via a
# PATH-prepended fake-bin directory -- the network boundary is the only
# thing mocked, so the version-comparison, sed/awk field-replacement, and
# $GITHUB_OUTPUT branches all run for real.
#
# Usage: ./check-ubuntu-netboot-release.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="${SCRIPT_DIR}/check-ubuntu-netboot-release.sh"

PASS=0
FAIL=0

# ── Fixture package.nix template ───────────────────────────────────────
# Two distinct placeholder hash values so a test can tell whether the
# amd64 (1st) and arm64 (2nd) `hash = "...";` fields got swapped or
# collapsed to the same value by a copy-paste bug in the awk pass.
fixture_package_nix() {
	local version="$1"
	cat <<EOF
{ stdenv, fetchurl }:
stdenv.mkDerivation {
  pname = "pxe-boot-grub-signed";
  version = "${version}";

  amd64Src = fetchurl {
    url = "https://releases.ubuntu.com/\${version}/ubuntu-\${version}-netboot-amd64.tar.gz";
    hash = "sha256-OLD_AMD64_HASH_PLACEHOLDER=";
  };

  arm64Src = fetchurl {
    url = "https://cdimage.ubuntu.com/releases/\${version}/release/ubuntu-\${version}-netboot-arm64.tar.gz";
    hash = "sha256-OLD_ARM64_HASH_PLACEHOLDER=";
  };
}
EOF
}

# ── Fake-bin stubs ──────────────────────────────────────────────────────
# One shared fake-bin dir setup per test case (each gets its own tmpdir),
# parameterized by $TEST_LISTING_VERSIONS (space-separated directory names
# as they'd appear in releases.ubuntu.com's HTML listing) and
# $TEST_AVAILABLE_VERSIONS (space-separated subset that actually has BOTH
# netboot tarballs present, i.e. passes curl --head for both URLs).
setup_fake_bin() {
	local fake_bin="$1"
	mkdir -p "$fake_bin"

	cat >"${fake_bin}/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
is_head=false
url=""
for a in "$@"; do
	case "$a" in
	--head) is_head=true ;;
	http*) url="$a" ;;
	esac
done

if [[ "$is_head" == true ]]; then
	v=""
	if [[ "$url" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
		v="${BASH_REMATCH[1]}"
	fi
	for ok in $TEST_AVAILABLE_VERSIONS; do
		[[ "$ok" == "$v" ]] && exit 0
	done
	exit 22
else
	for v in $TEST_LISTING_VERSIONS; do
		printf '<a href="%s/">%s/</a>\n' "$v" "$v"
	done
fi
STUB

	cat >"${fake_bin}/nix-prefetch-url" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# Real tool prints the hash on its own line (possibly preceded by a store
# path line); `tail -1` in the real script picks the last line either way.
# Derive a fake hash FROM the requested URL so amd64/arm64 naturally differ.
url="${*: -1}"
echo "fakehash-$(echo -n "$url" | md5sum | cut -c1-16)"
STUB

	cat >"${fake_bin}/nix" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# Only need to handle: nix hash convert --to sri --hash-algo sha256 <hash>
last="${*: -1}"
echo "sha256-${last}"
STUB

	chmod +x "${fake_bin}/curl" "${fake_bin}/nix-prefetch-url" "${fake_bin}/nix"
}

assert_contains() {
	local desc="$1" haystack="$2" needle="$3"
	if [[ "$haystack" == *"$needle"* ]]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL: $desc"
		echo "  expected to contain: $needle"
		echo "  actual: $haystack"
	fi
}

assert_not_contains() {
	local desc="$1" haystack="$2" needle="$3"
	if [[ "$haystack" != *"$needle"* ]]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL: $desc"
		echo "  expected NOT to contain: $needle"
		echo "  actual: $haystack"
	fi
}

# ── Test 1: bumps version and both hashes when a newer release exists ──
test_bumps_when_newer_release_available() {
	local tmp fake_bin package_nix github_output
	tmp=$(mktemp -d)
	fake_bin="${tmp}/bin"
	setup_fake_bin "$fake_bin"
	package_nix="${tmp}/package.nix"
	fixture_package_nix "24.04" >"$package_nix"
	github_output="${tmp}/github_output"
	: >"$github_output"

	PATH="${fake_bin}:${PATH}" \
		PACKAGE_NIX="$package_nix" \
		GITHUB_OUTPUT="$github_output" \
		TEST_LISTING_VERSIONS="24.04 26.04" \
		TEST_AVAILABLE_VERSIONS="24.04 26.04" \
		bash "$SCRIPT_UNDER_TEST"

	local out
	out=$(cat "$package_nix")
	assert_contains "version bumped to 26.04" "$out" 'version = "26.04";'
	assert_not_contains "old version no longer present" "$out" 'version = "24.04";'

	# amd64 hash (1st `hash = "...";`) and arm64 hash (2nd) must both be
	# replaced, and must differ from each other -- regression guard for
	# the exact bug class the awk n==1/n==2 counter was written to avoid
	# (a chained-sed re-match collapsing both fields to the same value).
	local amd64_hash arm64_hash
	amd64_hash=$(grep -A2 'amd64Src' "$package_nix" | grep -oP 'hash = "\K[^"]+' || true)
	arm64_hash=$(grep -A2 'arm64Src' "$package_nix" | grep -oP 'hash = "\K[^"]+' || true)
	assert_not_contains "amd64 hash no longer the old placeholder" "$amd64_hash" "OLD_AMD64_HASH_PLACEHOLDER"
	assert_not_contains "arm64 hash no longer the old placeholder" "$arm64_hash" "OLD_ARM64_HASH_PLACEHOLDER"
	if [[ "$amd64_hash" == "$arm64_hash" ]]; then
		FAIL=$((FAIL + 1))
		echo "FAIL: amd64 and arm64 hashes collapsed to the same value: $amd64_hash"
	else
		PASS=$((PASS + 1))
	fi

	local gh_out
	gh_out=$(cat "$github_output")
	assert_contains "GITHUB_OUTPUT reports bumped=true" "$gh_out" "bumped=true"
	assert_contains "GITHUB_OUTPUT reports new_version" "$gh_out" "new_version=26.04"

	rm -rf "$tmp"
}

# ── Test 2: no-op when already up to date ───────────────────────────────
test_noop_when_already_up_to_date() {
	local tmp fake_bin package_nix github_output
	tmp=$(mktemp -d)
	fake_bin="${tmp}/bin"
	setup_fake_bin "$fake_bin"
	package_nix="${tmp}/package.nix"
	fixture_package_nix "26.04" >"$package_nix"
	github_output="${tmp}/github_output"
	: >"$github_output"

	PATH="${fake_bin}:${PATH}" \
		PACKAGE_NIX="$package_nix" \
		GITHUB_OUTPUT="$github_output" \
		TEST_LISTING_VERSIONS="24.04 26.04" \
		TEST_AVAILABLE_VERSIONS="24.04 26.04" \
		bash "$SCRIPT_UNDER_TEST"

	local out gh_out
	out=$(cat "$package_nix")
	gh_out=$(cat "$github_output")
	assert_contains "package.nix untouched, still pinned to 26.04" "$out" 'version = "26.04";'
	assert_contains "amd64 placeholder hash untouched" "$out" "OLD_AMD64_HASH_PLACEHOLDER"
	assert_contains "GITHUB_OUTPUT reports bumped=false" "$gh_out" "bumped=false"

	rm -rf "$tmp"
}

# ── Test 3: refuses to "bump" to an older-sorting version ───────────────
test_refuses_non_forward_bump() {
	local tmp fake_bin package_nix github_output
	tmp=$(mktemp -d)
	fake_bin="${tmp}/bin"
	setup_fake_bin "$fake_bin"
	package_nix="${tmp}/package.nix"
	# Pinned version is NEWER than every candidate discovered on the
	# listing page -- e.g. a withdrawn/yanked release reordering things,
	# or (more realistically here) the only candidate with both tarballs
	# present sorting below what's already pinned.
	fixture_package_nix "26.04" >"$package_nix"
	github_output="${tmp}/github_output"
	: >"$github_output"

	PATH="${fake_bin}:${PATH}" \
		PACKAGE_NIX="$package_nix" \
		GITHUB_OUTPUT="$github_output" \
		TEST_LISTING_VERSIONS="24.04" \
		TEST_AVAILABLE_VERSIONS="24.04" \
		bash "$SCRIPT_UNDER_TEST"

	local out gh_out
	out=$(cat "$package_nix")
	gh_out=$(cat "$github_output")
	assert_contains "package.nix untouched, still pinned to 26.04" "$out" 'version = "26.04";'
	assert_contains "GITHUB_OUTPUT reports bumped=false" "$gh_out" "bumped=false"

	rm -rf "$tmp"
}

# ── Test 4: no-op when no candidate has both tarballs present ──────────
test_noop_when_no_candidate_has_both_tarballs() {
	local tmp fake_bin package_nix github_output
	tmp=$(mktemp -d)
	fake_bin="${tmp}/bin"
	setup_fake_bin "$fake_bin"
	package_nix="${tmp}/package.nix"
	fixture_package_nix "24.04" >"$package_nix"
	github_output="${tmp}/github_output"
	: >"$github_output"

	PATH="${fake_bin}:${PATH}" \
		PACKAGE_NIX="$package_nix" \
		GITHUB_OUTPUT="$github_output" \
		TEST_LISTING_VERSIONS="24.04 26.04" \
		TEST_AVAILABLE_VERSIONS="" \
		bash "$SCRIPT_UNDER_TEST"

	local out gh_out
	out=$(cat "$package_nix")
	gh_out=$(cat "$github_output")
	assert_contains "package.nix untouched, still pinned to 24.04" "$out" 'version = "24.04";'
	assert_contains "GITHUB_OUTPUT reports bumped=false" "$gh_out" "bumped=false"

	rm -rf "$tmp"
}

test_bumps_when_newer_release_available
test_noop_when_already_up_to_date
test_refuses_non_forward_bump
test_noop_when_no_candidate_has_both_tarballs

echo ""
echo "Passed: ${PASS}, Failed: ${FAIL}"
[[ "$FAIL" -eq 0 ]]
