{ lib
, pkgs
, ...
}:

rec {
  _regex_validate_ip_address_numbers =
    "([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])";
  _regex_validate_ip_address =
    "${_regex_validate_ip_address_numbers}(\.${_regex_validate_ip_address_numbers}){3}";
  _regex_validate_cidr =
    "(${_regex_validate_ip_address}/([1-9]|[1-2][0-9]|3[0-2]))";

  fromCidrString = cidr: (
    let
      result = builtins.fromJSON (
        lib.readFile "${
          pkgs.runCommand
          "fromCidrString"
          {
            buildInputs = [ pkgs.ipcalc ];
            env.cidr = cidr;
          }
          ''ipcalc --json "$cidr" > $out''
        }"
      );
    in
      {
        address = if builtins.hasAttr "ADDRESS" result
                  then result.ADDRESS
                  else null;
        addresses = lib.strings.toInt result.ADDRESSES;
        addrSpace = result.ADDRSPACE;
        broadcast = result.BROADCAST;
        maxAddr = result.MAXADDR;
        minAddr = result.MINADDR;
        netmask = result.NETMASK;
        network = result.NETWORK;
        prefix = lib.strings.toInt result.PREFIX;
      }
  );

  increase = {ip, by, subnet ? ""}: (
    let
    result = builtins.fromJSON (lib.readFile "${
      pkgs.runCommand
      "increase"
      {
        buildInputs = [ pkgs.python3 ];
        env.ip = ip;
        env.increase_size_by = by;
        env.verify_subnet = subnet;
        env._python_code = ''
          from sys import argv
          from ipaddress import ip_address, ip_network
          from json import dumps

          def err(msg):
            print(dumps({"err": True, "msg": msg}))
            exit(0)

          def ok(data):
            print(dumps({"err": False, "data": data}))
            exit(0)

          try:
            ip_tmp = argv[1].split("/")[0]
            ip = ip_address(ip_tmp)
          except:
            err(f"Invalid IPv4 address (arg: ip): {argv[1]}")

          try:
            increase_size_by = int(argv[2])
          except:
            err(f"Invalid number (arg: by): {argv[2]}")

          try:
            verify_subnet = ip_network(argv[3]) if argv[3] else None
          except:
            err(f"Invalid subnet (arg: subnet): {argv[3]}")

          new_ip = ip + increase_size_by
          if verify_subnet and new_ip not in verify_subnet:
            err(f"The ip address {new_ip} is not in the subnet {verify_subnet}")
          ok(f"{new_ip}")
        '';
      }
      ''python3 -c "$_python_code" "$ip" "$increase_size_by" "$verify_subnet" > $out''
    }");
  in
    if result.err
    then throw result.msg
    else result.data
  );

  decrease = {ip, by, subnet ? ""}: increase {inherit ip subnet; by = -1 * by;};

  cidrValid = (cidr: (builtins.match "^${_regex_validate_cidr}$" "${cidr}") != null);

  subnet = cidr_str: let
      cidr_attr = fromCidrString cidr_str;
    in
      if cidrValid cidr_str == false
      then throw "`${cidr_str}` is not a valid subnet"
      else if cidr_attr.prefix > 30
      then throw "The prefix length must be 30 or less for a valid subnet"
      else if cidr_attr.address != null
      then throw "`${cidr_str}` is an IP-address for the subnet `${cidr_attr.network}/${cidr_attr.prefix}`"
      else cidr_str
  ;

  subnetValid = cidr_str: ( builtins.tryEval ( subnet cidr_str ) ).success;

  ipAddressValid = (
    ipAddr: builtins.match "^${_regex_validate_ip_address}$"
    ipAddr != null
  );

  _regex_validate_multicast_address_numbers = "(22[4-9]|23[0-9])";
  _regex_validate_multicast_address =
    "${_regex_validate_multicast_address_numbers}(\.${_regex_validate_ip_address_numbers}){3}";
  multicastAddressValid = (mcAddr: builtins.match
    "^(${_regex_validate_multicast_address})$" mcAddr != null);

  fnValidMacAddress = (mac: (lib.match "([A-F0-9]{2}[:-]){5}[A-F0-9]{2}" (lib.strings.toUpper mac)) != null);
}
