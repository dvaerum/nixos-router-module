{
  lib,
  pkgs,
  options,
  netLib,
  ...
}:
let
  inherit (lib)
    mkOption
    mkOptionType
    literalExpression
    types
    ;

  inherit (lib.types)
    bool
    int
    ints
    str
    enum
    attrs
    anything
    nullOr
    listOf
    attrsOf
    attrTag
    either
    coercedTo
    submodule
    ;

  ipv4_fn = import ./functions/ipv4.nix { inherit lib netLib; };

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
      check = name: builtins.match "^([A-Za-z0-9._-]{1,15})$" name != null;
    };
    FQDN = mkOptionType {
      name = "FQDN";
      description = "FQDN (Fully Qualified Domain Name)";
      # To-do: This regex for matching FQDN my not be perfect and have bugs
      check = (
        domain:
        builtins.match "^((xn--)?[a-z0-9][a-z0-9-]{0,61}[a-z0-9]{0,1}[.](xn--)?([a-z0-9-]{1,61}|[a-z0-9-]{1,30}[.][a-z]){2,})$" domain
        != null
      );
    };
  };

  domainName = mkOption {
    description = "Provide list of Domain Name(s)";
    type = listOf networkTypes.FQDN;
    default = [ ];
  };

  setLeaseDatabase = mkOption {
    description = "Specify the type of lease database";
    type = submodule {
      options = {
        name = mkOption {
          description = "Set location for database lease file";
          type = types.path;
          default = /var/lib/kea/dhcp4.leases;
        };
        persist = mkOption {
          description = "Should the leases stored in the lease-file be persistent";
          type = bool;
          default = true;
        };
        type = mkOption {
          description = "Only the `memfile` option is available";
          type = enum [ "memfile" ];
          default = "memfile";
        };
      };
    };
    default = { };
  };

  setGeneralSettings = mkOption {
    description = "Config";
    type = submodule {
      options = {
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
      };
    };
    default = { };
  };

  setHooksLibraries = mkOption {
    description = ''
      Kea DHCPv4 hook libraries to load.
    '';
    type = submodule {
      options = {
        run_script = mkOption {
          description = ''
            Kea DHCPv4 `run_script` hook instances -- each entry calls
            `path` as `<path> <hook-point-name>` for every Kea DHCPv4
            hook point listed in `triggers`, with lease/query data
            passed via environment variables Kea itself sets
            (`LEASE4_*`, `QUERY4_*`, ...; see the Kea ARM's Run Script
            hook chapter for the full list per hook point).

            Keyed by an arbitrary name, not a fixed field, so more
            than one contributor -- this module's own DNS-lease
            publishing, plus anything else in your own configuration
            -- can each register an entry without conflicting.

            Unlike most Kea hooks, `run_script` cannot actually be
            loaded more than once: Kea logs a second `hooks-libraries`
            entry pointing at the same hook as "loaded" independently,
            but at runtime only the LAST one configured ever actually
            fires. So every entry here shares a single generated
            dispatcher script and a single real Kea `hooks-libraries`
            entry; `triggers` is how each one still only reacts to the
            hook points it cares about.
          '';
          type = attrsOf (submodule {
            options = {
              path = mkOption {
                description = "Path to the script to invoke.";
                type = str;
              };
              triggers = mkOption {
                description = ''
                  Which Kea DHCPv4 hook points to invoke `path` for.
                '';
                type = listOf (enum [
                  "leases4_committed"
                  "lease4_expire"
                  "lease4_release"
                  "lease4_renew"
                  "lease4_recover"
                  "lease4_decline"
                ]);
                default = [
                  "leases4_committed"
                  "lease4_expire"
                  "lease4_release"
                  "lease4_renew"
                  "lease4_recover"
                  "lease4_decline"
                ];
              };
              environment = mkOption {
                description = ''
                  Extra environment variables to set for `path`. Kea
                  itself never passes anything to a run_script beyond
                  the hook-point name, so this is how you get static
                  configuration into your script without writing your
                  own wrapper.
                '';
                type = attrsOf str;
                default = { };
              };
            };
          });
          default = { };
          example."my-hook" = {
            path = "/path/to/script.sh";
            triggers = [ "lease4_release" ];
          };
        };
      };
    };
    default = { };
  };

  setDhcpOptions = mkOption {
    description = ''
      Select if this network interface should be configured for DHCP Server or Client.
      It is also possible to just assign a static IP.
    '';
    default = null;
    type = nullOr (attrTag {
      static = mkOption {
        description = "To-do: make description (Note static IP is put here, but there may be a better location in the structure)";
        type = submodule {
          options = {
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
              example = [
                "192.168.1.1"
                "1.1.1.1"
              ];
              default = [ ];
            };
          };
        };
        default = { };
      };
      client = mkOption {
        description = "To-do: make description";
        type = bool;
        default = true;
      };
      server = mkOption {
        description = "To-do: make description";
        type = submodule {
          options = {
            id = mkOption {
              description = "Subnet IDs must be greater than zero and less than 4294967295";
              type = ints.between 1 4294967294;
              default = 1024;
            };
            address = mkOption {
              description = ''
                The router's own host IP on this subnet, in CIDR notation
                (e.g. `192.168.1.1/24`, not `192.168.1.0/24`). Sets the
                interface's IP and the DHCP subnet, and is the value `gateway`
                and `dns-servers` fall back to when left unset.
              '';
              type = networkTypes.CIDR;
              example = "192.168.1.1/24";
            };
            gateway = mkOption {
              description = ''
                Default route advertised to clients (kea `routers`):
                - `null` (the default): this router's own `address`.
                - an IP: advertise that address instead of this router.
                Only sent when `default-route` is true.
              '';
              type = nullOr networkTypes.ipAddress;
              default = null;
              example = "192.168.1.254";
            };
            dns-servers = mkOption {
              description = ''
                The DNS server(s) advertised to DHCP clients (kea
                `domain-name-servers`):
                - `null` (the default): advertise this router's own `address`.
                - `[ ]`: advertise no DNS server at all.
                - a non-empty list: advertise exactly those servers.
              '';
              type = nullOr (listOf networkTypes.ipAddress);
              default = null;
              example = [
                "192.168.1.1"
                "1.1.1.1"
              ];
            };
            default-route = mkOption {
              description = ''
                Whether to advertise a default route. `false` sends no
                `gateway`, so clients get no default route.
              '';
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
                Expose all other subnets, declared as a `dhcp.server.address`,
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
                  hostname = mkOption {
                    description = ''
                      DNS hostname for this reservation.

                      When set, `dns-server.enable` (this router's, not
                      just this interface's) publishes it as an A record
                      via the DHCP-lease hook -- always taking priority
                      over anything the client itself requests over DHCP,
                      regardless of `dns-server.publish-leases.enable`.
                    '';
                    type = nullOr str;
                    default = null;
                    example = "nas";
                  };
                };
              });
              default = { };
              example = {
                "00:11:22:33:44:55" = {
                  ip-address = "192.168.1.2";
                  hostname = "nas";
                };
              };
            };

            dns-server = {
              enable = mkOption {
                description = ''
                  Enable the DNS Server (Unbound) for this network interface.

                  Only takes effect when `my.router.dns-server.enable` is
                  also `true` — this is a per-interface opt-out, not an
                  independent switch.
                '';
                type = bool;
                default = true;
                example = false;
              };
              trust = mkOption {
                description = ''
                  Controls how DNS requests from this interface's subnet are
                  treated:

                  - `lan` (the default): the interface's own DNS-derived
                    records (reservations, DHCP pool leases) are published,
                    and `my.router.dns-server.spoof` rules are enforced.
                  - `forward-only`: requests are still resolved/forwarded,
                    but no spoof rules are applied and no local records are
                    published for this subnet. Intended for a trusted peer
                    network (e.g. a sibling router reached over a VXLAN
                    tunnel) that should be able to use this router as a
                    resolver without inheriting its spoof policy.
                '';
                type = enum [
                  "lan"
                  "forward-only"
                ];
                default = "lan";
                example = "forward-only";
              };
            };

            pxe-boot = {
              enable = mkOption {
                description = ''
                  Enable PXE Boot support for this network interface.

                  Side effect — DHCP client matching becomes MAC-only on this
                  subnet: enabling PXE boot sets kea's `match-client-id = false`
                  for the whole subnet, so ALL clients on it (pool and reserved)
                  are identified by MAC address only, and the DHCP client-id /
                  DUID is ignored.

                  Why: UEFI PXE firmware, the OS installer and the installed OS
                  present DIFFERENT DUID-derived client-ids for the SAME MAC. With
                  kea's default (client-id matching) a stale lease taken during
                  PXE/install blocks the installed OS from reclaiming its RESERVED
                  IP (it falls back to a pool address and needs a manual lease
                  drop). MAC-only matching makes a fixed reservation survive
                  firmware -> installer -> installed OS.

                  Trade-off: because it is subnet-wide, non-PXE hosts on this
                  subnet also lose client-id features (a NIC swap yields a new
                  identity/lease; a single MAC cannot host multiple logical DHCP
                  clients). Use a dedicated subnet for PXE provisioning if that
                  matters.
                '';
                type = bool;
                default = false;
                example = true;
              };
              defaultIso = mkOption {
                description = ''
                  Select which ISO file should be selected by default.
                '';
                type = str;
                default = "";
                example = "rhel-9.6-x86_64-dvd.iso";
              };
              defaultScriptName = mkOption {
                description = ''
                  Select which autoinstall script should be selected by default.
                '';
                type = str;
                default = "";
                example = "minimal-environment.kstart";
              };
              disableTftpServerWarning = mkOption {
                description = ''
                  Suppress the build-time warning that `tftpServer = false`
                  otherwise emits for this interface. Use once you've set up
                  your own TFTP server and no longer need the reminder.
                '';
                type = bool;
                default = false;
                example = true;
              };
            };

            tftpServer = mkOption {
              description = ''
                Whether this router should run a TFTP server (`atftpd`,
                bound to this interface's own address), serving
                `<tftpServer.root>/<id>` (see `tftpServerRoot` below to
                override the root for just this interface) for this
                subnet. Independent of `pxe-boot.enable` -- it can run
                standalone, with no PXE boot configured for this
                interface at all (the directory is then created empty;
                nothing stages files into it, so you populate it
                yourself).

                - `null` (the default): on when `pxe-boot.enable = true`,
                  off otherwise.
                - `true`: always on, pxe-boot or not.
                - `false`: always off.

                Effect on `pxe-boot`: this is what makes a PXE-boot-enabled
                subnet's grub/iPXE files (staged there regardless of this
                option) actually reachable over the network. Setting it
                `false` on such a subnet leaves those files staged but
                unserved -- you must run your own TFTP server against that
                same directory, or PXE clients there can't reach them.
                Triggers a build-time warning as a reminder (silence it
                with `pxe-boot.disableTftpServerWarning`).
              '';
              type = nullOr bool;
              default = null;
              example = true;
            };

            tftpServerRoot = mkOption {
              description = ''
                Override `my.router.tftpServer.root` for just this
                interface -- it still gets its own `<root>/<id>`
                subdirectory underneath. `null` (the default) inherits
                the global root.
              '';
              type = nullOr types.path;
              default = null;
              example = "/data/tftp-eth1";
            };

            clientClasses = mkOption {
              description = ''
                Define Kea client classes
                (see https://kea.readthedocs.io/en/latest/arm/classify.html)
                scoped to this subnet.

                Each class is forced into evaluation for this subnet only
                (Kea's `require-client-classes`), and its Kea class name is
                this attribute's name suffixed with this subnet's `id`
                (e.g. `my-class-204`), guaranteeing global uniqueness
                across interfaces -- the same convention the built-in
                PXE-boot classes already use.

                `test` (Kea's classification expression) is required;
                every other field (`option-data`, `next-server`,
                `boot-file-name`, etc.) is passed through to Kea verbatim
                in Kea's own JSON shape -- see the docs above for the full
                set of fields a class can carry.
              '';
              type = attrsOf (submodule {
                freeformType = attrsOf anything;
                options = {
                  test = mkOption {
                    description = "Kea classification test expression.";
                    type = str;
                  };
                };
              });
              default = { };
              example = {
                dect-setup-1 = {
                  test = "substring(option[60].hex,0,8) == 'dect-dev'";
                  option-data = [
                    {
                      name = "boot-file-name";
                      data = "dect-setup-1.efi";
                    }
                  ];
                };
              };
            };

            domainName = domainName;
          };
        };
        default = { };
      };
    });
  };

  networkInferfaceNameOptions = {
    name = mkOption {
      description = "Set the name of the network interface";
      type = networkTypes.interfaceName;
    };
  };

  interfaceSharedOptionsWithoutBridge = {
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
      description = "";
      type = bool;
      default = false;
    };

    ipMasquerade = mkOption {
      description = ''
        Enable ip masquerade (aka NAT) on the interface.

        This is needed e.g. if the interface is the WAN interface.
      '';
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
      default = [ ];
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

  interfaceSharedOptions = interfaceSharedOptionsWithoutBridge // {
    bridges = mkOption {
      description = ''
        Creating a bridge interface with and include this interface in the bridge.
      '';
      default = [ ];
      type = listOf (submodule {
        options = setBridgeOptions;
      });
    };
  };

  setBridgeOptions = {
    name = mkOption {
      description = ''
        Select the name of the bridge interface
      '';
      type = nullOr networkTypes.interfaceName;
      example = "br0";
    };
  };

  # Unicast (point-to-point) only; multicast `Group=`/BUM-flood mode would
  # touch the `pimd` wiring below, not needed for a two-router tunnel. Uses
  # the full `interfaceSharedOptions` (unlike bridges) so a VXLAN interface
  # can join a bridge OR carry its own `dhcp.static/client/server`.
  setVxlanOptions = {
    vni = mkOption {
      description = "VXLAN Network Identifier (VNI), 0-16777215.";
      type = ints.between 0 16777215;
      example = 1000;
    };

    local = mkOption {
      description = ''
        Source IP to bind/send from. `null` (the default) lets the kernel
        pick whatever address the routing table would use to reach
        `remote`.
      '';
      type = nullOr networkTypes.ipAddress;
      default = null;
    };

    remote = mkOption {
      description = ''
        The other tunnel endpoint's IP address (unicast point-to-point
        only, no multicast/BUM-flood mode in this module yet). Must be
        a static, currently-correct, routable IP: NOT a hostname, and NOT
        usable directly across NAT or a dynamic WAN IP on either end.
        This assumes both ends already sit on stable, mutually-routable
        infrastructure.
      '';
      type = networkTypes.ipAddress;
      example = "172.20.1.1";
    };

    destinationPort = mkOption {
      description = ''
        UDP port used for the encapsulated traffic. Defaults to the
        IANA-assigned standard (4789) rather than the Linux kernel's own
        historical non-standard default (8472), for interop with
        non-Linux VXLAN peers.
      '';
      type = types.port;
      default = 4789;
    };
  }
  // interfaceSharedOptions
  // networkInferfaceNameOptions;

  setVlanOptions = {
    id = mkOption {
      description = "Set VLan ID of the network interface";
      type = ints.between 1 4096;
      example = 1337;
    };

    name = mkOption {
      description = ''
        Option for setting the name of the VLAN
        Otherwise it will get the default name: vlan-<ID>
      '';
      type = nullOr networkTypes.interfaceName;
      default = null;
    };
  }
  // interfaceSharedOptions;

  setInterfaceOptions = {
    mac = mkOption {
      description = ''
        MAC address of the network interface.

        It can be either a MAC-address or list of MAC-addresses.

        **Example:** A list of MAC-addresses can make sense if you have multiple
        USB adapter which are not connected at the same time, but you want to have
        the same network interface name (and want to be configured the same)
      '';
      type = nullOr (either (listOf networkTypes.macAddress) networkTypes.macAddress);
    };

    # Alias for `systemd.network.links.<name>.linkConfig`,
    # but with the description updated to share this info.
    linkConfig =
      let
        description = ''
          Alias for `systemd.network.links.<name>.linkConfig`.

          Basically live copy-paste of the NixOS `options` for this systemd setting.
        '';
      in
      (
        # To-do: This if-else statement "hack" is done, because otherwise
        #        I would have to provide `pkgs.nixosOptionsDoc` with part of
        #        `systemd` module from NixOS otherwise `pkgs.nixosOptionsDoc`
        #        would fail.
        #        I hope to find a better way to handle this alias.
        if builtins.hasAttr "systemd" options then
          (
            (builtins.elemAt (builtins.elemAt options.systemd.network.links.type.getSubModules 0).imports 0)
            .options.linkConfig
            // {
              inherit description;
            }
          )
        else
          (mkOption {
            description = description;
            type = attrs;
          })
      );

    vlans = mkOption {
      description = ''
        Create a interface to handle VLAN tagged packages recieved on this interface.
      '';
      default = [ ];
      type = listOf (submodule {
        options = setVlanOptions;
      });
    };
  }
  // networkInferfaceNameOptions
  // interfaceSharedOptions;
in
{
  imports = [ ];
  options = {
    my.router = {
      enable = mkOption {
        description = "Enable Router module";
        type = bool;
        default = false;
        example = true;
      };

      configInterface = mkOption {
        description = "Config all physical/plain network interfaces";
        type = attrsOf (
          submodule (
            { name, ... }: {
              options = setInterfaceOptions;
              config.name = lib.mkDefault name;
            }
          )
        );
        default = { };
        example = {
          eth1 = {
            dhcp.static.ip-address = "10.0.1.2/24";
          };
        };
      };

      defaultRouteInterface = mkOption {
        description = "Name of the network interface with the default route";
        type = networkTypes.interfaceName;
        default = defaultInterfaceName;
      };

      defaultRouteMetric = mkOption {
        description = ''
          Set the matric (priority) for the default route,
          in case there are other services when also tries to config an default route.
        '';
        type = int;
        default = 75;
        example = 100;
      };

      bridgeInterfaces = mkOption {
        description = "Config all bridge interfaces";
        type = attrsOf (
          submodule (
            { name, ... }: {
              options = interfaceSharedOptionsWithoutBridge // networkInferfaceNameOptions;
              config.name = lib.mkDefault name;
            }
          )
        );
        default = { };
        example = {
          br0 = {
            dhcp.client = true;
          };
        };
      };

      vxlanInterfaces = mkOption {
        description = "Config all VXLAN (unicast point-to-point) interfaces";
        type = attrsOf (
          submodule (
            { name, ... }: {
              options = setVxlanOptions;
              config.name = lib.mkDefault name;
            }
          )
        );
        default = { };
        example = {
          vxlan1000 = {
            vni = 1000;
            remote = "172.20.1.1";
            dhcp.static.ip-address = "10.100.0.2/30";
          };
        };
      };

      dhcp.server = {
        generalSettings = setGeneralSettings;
        leaseDatabase = setLeaseDatabase;
        hooksLibraries = setHooksLibraries;
      };

      dns-server = {
        enable = mkOption {
          description = ''
            Enable the DNS Server (Unbound).

            When enabled, every `dhcp.server` interface gets its own DNS
            service, bound directly to that interface's own address (never
            `0.0.0.0`), unless that interface's own
            `dhcp.server.dns-server.enable` is set to `false`.
          '';
          type = bool;
          default = true;
          example = false;
        };

        spoof = {
          overrides = mkOption {
            description = ''
              Per-hostname DNS overrides (split-horizon redirects), applied
              via RPZ local-data. These always take priority over the real
              answer, on every interface with `dhcp.server.dns-server.trust
              = "lan"` (the default).
            '';
            type = attrsOf (coercedTo networkTypes.ipAddress lib.singleton (listOf networkTypes.ipAddress));
            default = { };
            example = {
              "nas.home.arpa" = [
                "10.0.0.5"
                "10.0.0.6"
              ];
              "printer.home.arpa" = "10.0.0.9";
            };
          };

          blocklist = {
            enable = mkOption {
              description = ''
                Enable ad/tracker DNS blocking via a periodically-fetched
                RPZ zone, built from the hosts-file-format lists in `urls`.
                Applied on every interface with
                `dhcp.server.dns-server.trust = "lan"`.
              '';
              type = bool;
              default = false;
              example = true;
            };

            urls = mkOption {
              description = ''
                hosts-file-format blocklist URLs (e.g. StevenBlack/hosts,
                oisd). Fetched and converted to an RPZ zonefile on the
                schedule set by `updateInterval`; the fetch is a runtime
                network call, not pinned/reproducible like the rest of this
                module.
              '';
              type = listOf str;
              default = [ ];
              example = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
            };

            updateInterval = mkOption {
              description = ''
                systemd `OnCalendar` spec for how often the blocklist is
                re-fetched.
              '';
              type = str;
              default = "daily";
              example = "hourly";
            };
          };
        };

        publish-leases = {
          enable = mkOption {
            description = ''
              Also publish an A record for dynamic (non-reserved) DHCP
              pool leases, using the hostname the client itself sends
              over DHCP (option 12) -- sanitized by Kea
              (`hostname-char-set`), and rejected outright if it collides
              with any reservation's `hostname` or `dns-server.spoof.overrides`
              entry.

              Off by default: unlike a reservation's `hostname` (admin-
              authored), a pool client's hostname is unauthenticated
              input from whatever device asks for an address -- turning
              this on means trusting that input enough to serve it back
              as a real DNS answer on the LAN.
            '';
            type = bool;
            default = false;
            example = true;
          };
        };
      };

      pxe-boot = {
        enable = mkOption {
          description = ''
            Enable support for PXE Boot.

            This will download PXE boot binaries and
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
          type = types.path;
          example = "/data/iso";
        };
        nixIsos = mkOption {
          description = ''
            ISO images built by Nix (e.g. this project's own
            `modules/iso-builder`) to serve for PXE boot, without needing
            to manually copy them into `isoFolderPath`. Each package is
            exposed via a `systemd.tmpfiles.rules "L+"` symlink farm --
            atomic and generation-pinned: removing a package from this
            list changes what the farm contains on the next switch, so no
            manually-managed symlinks can be orphaned.

            Inert unless `pxe-boot.enable` is also set -- the farm and
            its `tmpfiles.rules` entry only exist inside that same
            `lib.mkIf`.

            `autoinstall` and each interface's `defaultIso` key by ISO
            same as for `isoFolderPath`-discovered ISOs -- there is
            nothing `nixIsos`-specific to configure on that side, just
            use the same filename there too.
          '';
          default = [ ];
          example = literalExpression "[ self.packages.x86_64-linux.iso-x86_64 ]";
          type = types.listOf types.package;
        };
        nixIsosDir = mkOption {
          description = ''
            Where the `nixIsos` symlink farm is exposed via
            `systemd.tmpfiles.rules "L+"` (added to `isoFolderPaths`
            alongside the manually-managed `isoFolderPath` whenever
            `nixIsos` is non-empty).
          '';
          type = types.path;
          default = "/var/lib/pxe-boot/nix-isos";
        };
        isoDownloadRateLimit = mkOption {
          description = ''
            Caps the transfer rate of whole-ISO downloads served under
            `/isos/` (nginx's `limit_rate`, e.g. a client's own
            `findiso=` fetch). `null` (the default) means unlimited.

            A bulk ISO transfer and other clients' latency-sensitive GRUB
            kernel/initrd fetches share the same nginx worker process;
            on a very weak/single-core router this can starve those
            latency-sensitive requests enough to make GRUB's legacy
            BIOS/SeaBIOS PXE network driver (which has no retry logic)
            fail entirely. Real routers typically have enough cores that
            this never actually contends -- this project's own E2E test
            runs its router VM with a single vCPU and sets this
            explicitly, which real deployments normally won't need to.
          '';
          default = null;
          example = "20m";
          type = types.nullOr types.str;
        };
        shimPackage = mkOption {
          description = ''
            The signed shim + GRUB build served over TFTP as
            `bootx64.efi`/`bootaa64.efi` for UEFI Secure Boot clients
            (see `tests/pxe-boot/secure-boot.nix`). Overridable so an
            operator can supply their own MOK-enrolled shim, pin a
            different Ubuntu netboot release than this module's own
            auto-bumped default, or substitute a signed build obtained
            through a different trust chain entirely -- without forking
            this module.

            Defaults to this project's own `pxe-boot-grub-signed`
            package (`packages/pxe-boot-grub-signed/package.nix`),
            Canonical/Microsoft-signed shim + GRUB repackaged from
            Ubuntu's netboot tarball.
          '';
          type = types.package;
          default = import ./../packages/pxe-boot-grub-signed/package.nix { inherit pkgs; };
          defaultText = literalExpression "pkgs.callPackage ../packages/pxe-boot-grub-signed/package.nix { }";
          example = literalExpression "pkgs.my-custom-signed-grub";
        };
        autoinstall = mkOption {
          description = ''
            Configure autoinstall script for the different ISOs
          '';
          default = { };
          example = {
            "rhel-9.6-x86_64-dvd.iso" = {
              scriptName = "minimal-environment.kstart";
              script = ./path/to/script.kstart;
            };
          };
          type = attrsOf (
            listOf (submodule {
              options = {
                scriptName = mkOption {
                  description = ''
                    Name of the script in the GRUB Menu.
                  '';
                  type = str;
                  example = "minimal-environment.kstart";
                };
                script = mkOption {
                  description = ''
                    Provide the content of the script or the path to the script.

                    SECURITY: a literal string value here is written to
                    the world-readable Nix store (/nix/store) and served
                    completely unauthenticated over plain HTTP on the
                    LAN (anyone who can reach this router's network can
                    download it). Do not put secrets -- passwords, API
                    keys, private keys -- directly in this value. Use a
                    path to a file managed by a proper secrets mechanism
                    (e.g. sops-nix) if the script needs to reference a
                    secret, and have the installer itself fetch/decrypt
                    it at install time instead.
                  '';
                  type = either types.path str;
                  example = ./path/to/script.kstart;
                };
              };
            })
          );
        };
      };

      tftpServer = {
        root = mkOption {
          description = ''
            Base directory TFTP-serving interfaces stage files under and
            atftpd serves from -- each interface gets its own
            `<root>/<id>` subdirectory. pxe-boot follows this same root
            for the grub/iPXE files it stages; it does not have its own
            separate path setting.

            Override per-interface with
            `dhcp.server.tftpServerRoot`.
          '';
          type = types.path;
          default = "/srv/pxeboot";
          example = "/data/tftp";
        };
      };
    };
  };
  config = { };
}
