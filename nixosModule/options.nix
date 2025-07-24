{ lib
, pkgs
, options
, ...
}:

let
  inherit (lib)
    mkOption
    mkOptionType
  ;


  inherit (lib.types)
    bool
    int
    ints
    str
    path
    package
    enum
    attrs

    nullOr
    listOf
    attrsOf
    attrTag
    either

    submodule
  ;


  ipv4_fn = import ./functions/ipv4.nix { inherit lib pkgs; };

  defaultInterfaceName = "builtin-ether";

  networkTypes = {
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
    type = listOf networkTypes.FQDN;
    default = [];
  };

  setLeaseDatabase = with lib; mkOption {
    description = "Specify the type of lease database";
    type = submodule { options = {
      name = mkOption {
        description = "Set location for database lease file";
        type = path;
        default = /var/lib/kea/dhcp4.leases;
      };
      persist = mkOption {
        description = "Should the leases stored in the lease-file be persistent";
        type = bool;
        default = true;
      };
      type = mkOption {
        description = "Only the `memfile` option is available";
        type = enum ["memfile"];
        default = "memfile";
      };
    };};
    default = {};
  };

  setGeneralSettings = with lib; mkOption {
    description = "Config";
    type = submodule { options = {
      rebindTimer = mkOption {
        description = "Set rebind time (seconds)";
        type = int;
        default = 2000;
      };
      renewTimer = mkOption {
        description = "Set renew time (seconds)";
        type = int;
        default = 1000;
      };
      validLifetime = mkOption {
        description = "Set valid lifetime (seconds)";
        type = int;
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
    type = nullOr (
      attrTag {
        static = mkOption {
          description = "To-do: make description (Note static IP is put here, but there may be a better location in the structure)";
          type = submodule { options = {
            ip-address = mkOption {
              description = "
                Set the ip and subnet in the CIDR format.
              ";
              type = networkTypes.CIDR;
              example = "192.168.1.10/24";
            };
            gateway = mkOption {
              description = "Set the IP address of the gateway";
              type = nullOr networkTypes.ipAddress;
              example = "192.168.1.1";
              default = null;
            };
            dns-servers = mkOption {
              description = "Set the IP address(es) of the dns-server(s)";
              type = listOf networkTypes.ipAddress;
              example = ["192.168.1.1" "1.1.1.1"];
              default = [];
            };
          };};
          default = {};
        };
        client = mkOption {
          description = "To-do: make description";
          type = bool;
          default = true;
        };
        server = mkOption {
          description = "To-do: make description";
          type = submodule { options = {
            id = mkOption {
              description = "Subnet IDs must be greater than zero and less than 4294967295";
              type = ints.between 1 4294967294;
              default = 1024;
            };
            gateway = mkOption {
              description = "Set the gateway for the subnet";
              type = networkTypes.CIDR;
              default = "";
            };
            default-route = mkOption {
              description = "Provide DHCP clients with a default route";
              type = bool;
              default = true;
              example = false;
            };
            firstIP = mkOption {
              description = ''
                Set the first IP address provides by the DHCP Server.
                Example: `10` for subnet `192.168.1.0/24`
                          will be calculated to `192.168.1.10`.
                '';
              type = int;
              default = 5;
            };

            classless-static-route = mkOption {
              description = ''
                Expose all other subnets, declared as a `dhcp.server.gateway`,
                as a classless static route (Option: 121).
              '';
              type = bool;
              default = false;
              example = true;
            };

            reservations-only = mkOption {
              description = ''
                Only reply to the client which matches the information in `dhcp.server.reservations`.
              '';
              type = bool;
              default = false;
              example = true;
            };

            reservations = mkOption {
              description = ''
                Make reservations (MAC address specific configurations).
                Example: Make it so that one IP address is always provided to
                         the selected MAC address.
              '';
              type = attrsOf (submodule {
                options = {
                  ip-address = mkOption {
                    description = ''
                      Bind the IP address the MAC address (attribute key)
                    '';
                    type = nullOr networkTypes.ipAddress;
                    default = null;
                  };
                };
              });
              default = {};
              example = { "00:11:22:33:44:55" = { ip-address = "192.168.1.2"; }; };
            };

            ipxe-boot = {
              enable = mkOption {
                description = ''
                  Enable iPXE Boot support for this network interface.
                '';
                type = bool;
                default = false;
                example = true;
              };
              environment = mkOption {
                description = ''
                  Name of the boot environment.
                '';
                type = str;
                example = "RHEL9.6";
              };
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
      type = bool;
      default = true;
    };

    excludeFromNetworkManager = mkOption {
      description = ''
        Ensure that the interface is excluded from NetworkManager
      '';
      type = bool;
      default = false;
    };

    multicast = mkOption {
      description = '''';
      type = bool;
      default = false;
    };

    ipMasquerade = mkOption {
      description = '''';
      type = bool;
      default = false;
    };

    staticRoutes = mkOption {
      description = ''
        Added static routes for the interface.

        In the case of `dhcp.static`,
        if the route should be configured as the default use `0.0.0.0/0`.
      '';
      type = listOf networkTypes.subnet;
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
      type = nullOr bool;
      default = null;
      example = true;
    };
  };

  setBridgeOptions = with lib; {
    name = mkOption {
      description = ''
        Select the name of the bridge interface
      '';
      type = nullOr networkTypes.interfaceName;
      example = "br0";
    };
  };

  setVlanOptions = with lib; {
    id = mkOption {
      description = "Set VLan ID of the network interface";
      type = ints.between 1 4096;
      default = 0;
    };

    name = mkOption {
      description = ''
        Option for setting the name of the VLAN
        Otherwise it will get the default name: vlan-<ID>
      '';
      type = nullOr networkTypes.interfaceName;
      default = null;
    };
  } // interfaceSharedOptions;

  setInterfaceOptions = with lib; {
    mac = mkOption {
      description = "MAC address of the network interface";
      type = nullOr networkTypes.macAddress;
    };

    name = mkOption {
      description = "Set the name of the network interface";
      type = networkTypes.interfaceName;
#       default = "${defaultInterfaceName}";
    };

    # Alias for `systemd.network.links.<name>.linkConfig`,
    # but with the description updated to share this info.
    linkConfig = let
      description = ''
        Alias for `systemd.network.links.<name>.linkConfig`.

        Basically live copy-paste of the NixOS `options` for this systemd setting.
      '';
    in (
      # To-do: This if-else statement "hack" is done, because otherwise
      #        I would have to provide `pkgs.nixosOptionsDoc` with part of
      #        `systemd` module from NixOS otherwise `pkgs.nixosOptionsDoc`
      #        would fail.
      #        I hope to find a better way to handle this alias.
      if builtins.hasAttr "systemd" options
      then (
        ( builtins.elemAt
          ( builtins.elemAt
            options.systemd.network.links.type.getSubModules
            0
          ).imports
          0
        ).options.linkConfig // { inherit description; }
      )
      else (
        mkOption {
          description = description;
          type = attrs;
        }
      )
    );

    vlans = mkOption {
      description = ''
        Create a interface to handle VLAN tagged packages recieved on this interface.
      '';
      default = [];
      type = listOf (submodule {options = setVlanOptions;});
    };

    bridges = mkOption {
      description = ''
        Creating a bridge interface with and include this interface in the bridge.
      '';
      default = [];
      type = listOf (submodule {options = setBridgeOptions;});
    };
  } // interfaceSharedOptions;

in {
  imports = [];
  options = {
    my.router = {
      enable = mkOption {
        description = "Enable Router module";
        type = bool;
        default = false;
        example = true;
      };

      configInterface = mkOption {
        description = "List of configured network interfaces";
        type = listOf (submodule {options = setInterfaceOptions;});
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


      ipxe-boot = {
        enable = mkOption {
          description = ''
            Enable support for iPXE Boot.

            This will download iPXE boot binaries and
            prepare supported Linux distrobutions for download.
          '';
          type = bool;
          default = false;
          example = true;
        };
        isoFolderPath = mkOption {
          description = ''
            Path to the folder which contains the iso files.
          '';
          type = path;
          example = "/data/iso";
        };
        environments = mkOption {
          description = ''
            Configure distrobutions which can be iPXE Booted.
          '';
          default = {};
          example = {"RHEL9.6" = {isoName = "rhel-9.6-x86_64-dvd.iso"; type = "RHEL";};};
          type = attrsOf (submodule { options = {
            isoName = mkOption {
              description = ''
                Name of the ISO file which should be booted.
              '';
              type = str;
              example = "rhel-9.6-x86_64-dvd.iso";
            };
            type = mkOption {
              description = ''
                Select the provider of the ISO file.
              '';
              type = enum ["RHEL"];
              example = "RHEL";
            };
            kStartScript = mkOption {
              description = ''
                If a kstart-script is provided
                it will be used to create an unattented install
                of the new OS.
              '';
              type = nullOr (either path str);
              default = null;
              example = ./path/to/script.kstart;
            };
          };});
        };
      };
    };
  };
  config = {};
}
