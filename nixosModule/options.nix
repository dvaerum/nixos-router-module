{ lib
, pkgs
, options
, ...
}:

let

  ipv4_fn = import ./functions/ipv4.nix { inherit lib pkgs; };

  defaultInterfaceName = "builtin-ether";

  networkTypes = with lib; {
    macAddress = mkOptionType {
      name = "macAddress";
      description = "Mac Address (use `:` or `-` as separator)";
      check = ipv4_fn.fnValidMacAddress;
    };
    ipAddress = mkOptionType {
      name = "ipAddress";
      description = "IP address";
      check = ipv4_fn.ipAddressValid;
    };
    subnet = mkOptionType {
      name = "subnet";
      description = "Subnet";
      check = ipv4_fn.subnetValid;
    };
    multicastAddress = mkOptionType {
      name = "multicastAddress";
      description = "Multicast Address (240.0.0.0 - 239.255.255.255)";
      check = ipv4_fn.multicastAddressValid;
    };
    CIDR = mkOptionType {
      name = "CIDR";
      description = "CIDR (IP and Subnet. Example: 192.168.1.4/24)";
      check = ipv4_fn.cidrValid;
    };
    interfaceName = mkOptionType {
      name = "interfaceName";
      description = "Network Interface Name ()";
      check = (name: builtins.match "^([A-Za-z0-9._-]{1,15})$" name != null);
    };
    FQDN = mkOptionType {
      name = "FQDN";
      description = "FQDN (Fully Qualified Domain Name)";
      # To-do: This regex for matching FQDN my not be perfect and have bugs
      check = (domain: builtins.match ("^((xn--)?[a-z0-9][a-z0-9-]{0,61}[a-z0-9]{0,1}[.](xn--)?([a-z0-9-]{1,61}|[a-z0-9-]{1,30}[.][a-z]){2,})$") domain != null);
    };
  };

  domainName = with lib; mkOption {
    description = "Provide list of Domain Name(s)";
    type = types.listOf networkTypes.FQDN;
    default = [];
  };

  setLeaseDatabase = with lib; mkOption {
    description = "Specify the type of lease database";
    type = types.submodule { options = {
      name = mkOption {
        description = "Set location for database lease file";
        type = types.path;
        default = /var/lib/kea/dhcp4.leases;
      };
      persist = mkOption {
        description = "Should the leases stored in the lease-file be persistent";
        type = types.bool;
        default = true;
      };
      type = mkOption {
        description = "Only the `memfile` option is available";
        type = types.enum ["memfile"];
        default = "memfile";
      };
    };};
    default = {};
  };

  setGeneralSettings = with lib; mkOption {
    description = "Config";
    type = types.submodule { options = {
      rebindTimer = mkOption {
        description = "Set rebind time (seconds)";
        type = types.int;
        default = 2000;
      };
      renewTimer = mkOption {
        description = "Set renew time (seconds)";
        type = types.int;
        default = 1000;
      };
      validLifetime = mkOption {
        description = "Set valid lifetime (seconds)";
        type = types.int;
        default = 4000;
      };
      domainName = domainName;
    };};
    default = {};
  };

  setDhcpOptions = with lib; mkOption {
    description = ''
      Select if this network interface should be configured for DHCP Server or Client.
      It is also possible to just assign a static IP.
    '';
    default = null;
    type = types.nullOr (
      types.attrTag {
        static = mkOption {
          description = "To-do: make description (Note static IP is put here, but there may be a better location in the structure)";
          type = types.submodule { options = {
            ip-address = mkOption {
              description = "
                Set the ip and subnet in the CIDR format.
              ";
              type = networkTypes.CIDR;
              example = "192.168.1.10/24";
            };
            gateway = mkOption {
              description = "Set the IP address of the gateway";
              type = types.nullOr networkTypes.ipAddress;
              example = "192.168.1.1";
              default = null;
            };
            dns-servers = mkOption {
              description = "Set the IP address(es) of the dns-server(s)";
              type = types.listOf networkTypes.ipAddress;
              example = ["192.168.1.1" "1.1.1.1"];
              default = [];
            };
          };};
          default = {};
        };
        client = mkOption {
          description = "To-do: make description";
          type = types.bool;
          default = true;
        };
        server = mkOption {
          description = "To-do: make description";
          type = types.submodule { options = {
            id = mkOption {
              description = "Subnet IDs must be greater than zero and less than 4294967295";
              type = types.ints.between 1 4294967294;
              default = 1024;
            };
            gateway = mkOption {
              description = "Set the gateway for the subnet";
              type = networkTypes.CIDR;
              default = "";
            };
            default_route = mkOption {
              description = "Provide DHCP clients with a default route";
              type = types.bool;
              default = true;
              example = false;
            };
            firstIP = mkOption {
              description = ''
                Set the first IP address provides by the DHCP Server.
                Example: `10` for subnet `192.168.1.0/24`
                          will be calculated to `192.168.1.10`.
                '';
              type = types.int;
              default = 5;
            };

            classless-static-route = mkOption {
              description = ''
                Expose all other subnets, declared as a `dhcp.server.gateway`,
                as a classless static route (Option: 121).
              '';
              type = types.bool;
              default = false;
              example = true;
            };

            reservations-only = mkOption {
              description = '''';
              type = types.bool;
              default = false;
            };

            reservations = mkOption {
              description = ''
                Make reservations (MAC address specific configurations).
                Example: Make it so that one IP address is always provided to
                         the selected MAC address.
              '';
              type = types.attrsOf (types.submodule {
                options = {
                  ip-address = mkOption {
                    description = ''
                      Bind the IP address the MAC address (attribute key)
                    '';
                    type = types.nullOr networkTypes.ipAddress;
                    default = null;
                  };
                };
              });
              default = {};
              example = { "00:11:22:33:44:55" = { ip-address = "192.168.1.2"; }; };
            };

            domainName = domainName;
          };};
          default = {};
        };
      }
    );
  };

  interfaceSharedOptions = with lib; {
    dhcp = setDhcpOptions;

    forwarding = mkOption {
      description = ''
        IPv4 forwarding. It is turn on by default.
      '';
      type = types.bool;
      default = true;
    };

    excludeFromNetworkManager = mkOption {
      description = ''
        Ensure that the interface is excluded from NetworkManager
      '';
      type = types.bool;
      default = false;
    };

    multicast = mkOption {
      description = '''';
      type = types.bool;
      default = false;
    };

    ipMasquerade = mkOption {
      description = '''';
      type = types.bool;
      default = false;
    };

    staticRoutes = mkOption {
      description = ''
        Added static routes for the interface.

        In the case of `dhcp.static`,
        if the route should be configured as the default use `0.0.0.0/0`.
      '';
      type = types.listOf networkTypes.subnet;
      default = [];
      example = [ "172.20.90.0/24" ];
    };

    requiredForOnline = mkOption {
      description = ''
        When configured to `null` (which is the default).

        - requiredForOnline will be set to `true`
          if the interface is configured as `dhcp.server`.

        - requiredForOnline will be set to `false`
          if the interface is configured as `dhcp.client` or `dhcp.static`.

        This behavior can be overwritten by configuring this option to `true` and
        the `systemd-networkd-wait-online.service` will
        wait for this interface to be configured (until timeout).
        Or set the option to `false` for the `systemd-networkd-wait-online.service`
        to ignore this interface.
      '';
      type = types.nullOr types.bool;
      default = null;
      example = true;
    };
  };

  setBridgeOptions = with lib; {
    name = mkOption {
      description = ''
        Select the name of the bridge interface
      '';
      type = types.nullOr networkTypes.interfaceName;
      example = "br0";
    };
  };

  setVlanOptions = with lib; {
    id = mkOption {
      description = "Set VLan ID of the network interface";
      type = types.ints.between 1 4096;
      default = 0;
    };

    name = mkOption {
      description = ''
        Option for setting the name of the VLAN
        Otherwise it will get the default name: vlan-<ID>
      '';
      type = types.nullOr networkTypes.interfaceName;
      default = null;
    };
  } // interfaceSharedOptions;

  setInterfaceOptions = with lib; {
    mac = mkOption {
      description = "MAC address of the network interface";
      type = networkTypes.macAddress;
      default = "";
    };

    name = mkOption {
      description = "Set the name of the network interface";
      type = networkTypes.interfaceName;
      default = "${defaultInterfaceName}";
    };

    # Alias for `systemd.network.links.<name>.linkConfig`,
    # but with the description updated to share this info.
    linkConfig = (
      builtins.elemAt
      ( builtins.elemAt
        options.systemd.network.links.type.getSubModules
        0
      ).imports
      0
    ).options.linkConfig // {
      description = ''
        Alias for `systemd.network.links.<name>.linkConfig`.

        Basically live copy-paste of the NixOS `options` for this systemd setting.
      '';
    };

    vlans = mkOption {
      default = [];
      type = types.listOf (types.submodule {options = setVlanOptions;});
    };

    bridges = mkOption {
      default = [];
      type = types.listOf (types.submodule {options = setBridgeOptions;});
    };
  } // interfaceSharedOptions;

in

  {
    my.router = with lib; {
      enable = mkOption {
        description = "Enable Router module";
        type = types.bool;
        default = false;
        example = true;
      };

      configInterface = mkOption {
        description = "List of configured network interfaces";
        type = types.listOf (types.submodule {options = setInterfaceOptions;});
        default = [];
      };

      defaultRouteInterface = mkOption {
        description = "Name of the network interface with the default route";
        type = networkTypes.interfaceName;
        default = defaultInterfaceName;
      };

      dhcp.server = {
        generalSettings = setGeneralSettings;
        leaseDatabase = setLeaseDatabase;
      };
    };
  }
