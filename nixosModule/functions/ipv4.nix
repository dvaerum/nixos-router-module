{
  lib,
  netLib,
  ...
}:
# `netLib` is the pure-Nix IP library (github:0xCCF4/nix-net-lib), threaded in via
# the flake's `_module.args`. It replaces the previous `ipcalc`/`python3`
# import-from-derivation helpers, so IP math now happens purely at eval time.
rec {
  _regex_validate_ip_address_numbers = "([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])";
  _regex_validate_ip_address = "${_regex_validate_ip_address_numbers}(\.${_regex_validate_ip_address_numbers}){3}";
  _regex_validate_cidr = "(${_regex_validate_ip_address}/([1-9]|[1-2][0-9]|3[0-2]))";

  # Strip the trailing `/prefix` that netLib's assignAddress returns.
  _stripMask = s: builtins.head (lib.strings.splitString "/" s);

  # The `index`-th address of a network (in CIDR notation), without the trailing
  # `/prefix`. Thin wrapper over netLib.assignAddress; throws when `index` is out
  # of range for the network's mask.
  nthAddress = network: index: _stripMask (netLib.assignAddress network index);

  # Parse a CIDR string into the ipcalc-shaped attrset the module expects.
  # Kept field-for-field compatible with the old `ipcalc --json` version:
  #   address : the host address, or `null` for a bare network address
  #             (the `subnet` validator relies on this to reject host CIDRs)
  #   network : network address (no mask)
  #   netmask : dotted netmask
  #   prefix  : prefix length as an int (compared with `> 30` downstream)
  #   addresses, minAddr, maxAddr, broadcast : usable-host count + range
  fromCidrString = cidr: (
    let
      d = netLib.ip4.decompose cidr;
      mask = d.mask;
      total = netLib.pow 2 (32 - mask);
      nth = nthAddress d.network;
    in {
      address =
        if d.addressParts == d.networkParts
        then null
        else d.addressNoMask;
      network = d.networkNoMask;
      netmask = d.networkMaskNoMask;
      prefix = mask;
      addresses = total - 2;
      minAddr = nth 1;
      maxAddr = nth (total - 2);
      broadcast = nth (total - 1);
    }
  );

  cidrValid = cidr: (builtins.match "^${_regex_validate_cidr}$" "${cidr}") != null;

  subnet = cidr_str: let
    cidr_attr = fromCidrString cidr_str;
  in
    if cidrValid cidr_str == false
    then throw "`${cidr_str}` is not a valid subnet"
    else if cidr_attr.prefix > 30
    then throw "The prefix length must be 30 or less for a valid subnet"
    else if cidr_attr.address != null
    then throw "`${cidr_str}` is an IP-address for the subnet `${cidr_attr.network}/${builtins.toString cidr_attr.prefix}`"
    else cidr_str;

  subnetValid = cidr_str: (builtins.tryEval (subnet cidr_str)).success;

  ipAddressValid = (
    ipAddr:
      builtins.match "^${_regex_validate_ip_address}$"
      ipAddr
      != null
  );

  _regex_validate_multicast_address_numbers = "(22[4-9]|23[0-9])";
  _regex_validate_multicast_address = "${_regex_validate_multicast_address_numbers}(\.${_regex_validate_ip_address_numbers}){3}";
  multicastAddressValid = mcAddr:
    builtins.match
    "^(${_regex_validate_multicast_address})$"
    mcAddr
    != null;

  fnValidMacAddress = mac: (lib.match "([A-F0-9]{2}[:-]){5}[A-F0-9]{2}" (lib.strings.toUpper mac)) != null;
}
