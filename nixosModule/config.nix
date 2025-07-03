{ pkgs
, config
, lib
,  ...
}: let

  functions-general = import ./functions/general.nix { inherit pkgs lib config; };
  inherit (functions-general)
    # To-do: Re-visit the use of this function,
    #        now that I know more there may be a better way of doing this
    recursiveMerge

    cfg
    cfgConfigInterface
    cfgDefaultRouteInterface

    cfgSetDhcpServerInterfaceOnly

    vlanName
    vlanFilename
    bridgeFilename
    interfaceFilename

    allInterfaces
    systemdNetworkDHCP
  ;


  ipv4_fn = import ./functions/ipv4.nix { inherit lib pkgs; };

in (
  lib.mkIf cfg.enable {
    systemd.network = /*lib.debug.traceValSeq*/ ( recursiveMerge (
      lib.lists.forEach
      cfgConfigInterface
      ( interface_conf: {
        links = {
          "${interfaceFilename interface_conf.name}" = {
            matchConfig.PermanentMACAddress = interface_conf.mac;
            linkConfig = interface_conf.linkConfig // {
              Name = interface_conf.name;
            };
          };
        };

        networks = {
          "${interfaceFilename interface_conf.name}" = {
            enable = true;
            matchConfig.Name = interface_conf.name;
            vlan = lib.lists.forEach interface_conf.vlans (vlan_conf: vlanName vlan_conf);
            bridge = lib.lists.forEach interface_conf.bridges (bridge_conf: bridge_conf.name);
          } // systemdNetworkDHCP {
            interfaceName = interface_conf.name;
            interfaceConf = interface_conf;
          };
        } // builtins.listToAttrs (lib.lists.forEach interface_conf.vlans (vlan_conf: {
          name = vlanFilename vlan_conf;
          value = {
            enable = true;
            matchConfig.Name = vlanName vlan_conf;
          } // systemdNetworkDHCP {
            interfaceName = vlanName vlan_conf;
            interfaceConf = vlan_conf;
          };
        })) // builtins.listToAttrs (lib.lists.forEach interface_conf.bridges (bridge_conf: {
          name = bridgeFilename bridge_conf;
          value = {
            enable = true;
            matchConfig.Name = bridge_conf.name;
            linkConfig = {
              RequiredForOnline = lib.mkDefault false;
            };
            networkConfig = {
              LinkLocalAddressing = lib.mkDefault "no";
            };
          };
        }))
        ;

        netdevs = (
          builtins.listToAttrs (lib.lists.forEach interface_conf.vlans (vlan_conf: {
            name = vlanFilename vlan_conf;
            value = {
              enable = true;
              netdevConfig = {
                Kind = "vlan";
                Name = vlanName vlan_conf;
              };

              vlanConfig = { Id = vlan_conf.id; };
            };
          }))
        )
        //
        (
          builtins.listToAttrs (lib.lists.forEach interface_conf.bridges (bridge_conf: {
            name = bridgeFilename bridge_conf;
            value = {
              enable = true;
              netdevConfig = {
                Kind = "bridge";
                Name = bridge_conf.name;
              };
            };
          }))
        )
        ;

        wait-online.ignoredInterfaces =
          lib.optionals
          ( interface_conf.dhcp == null )
          [ interface_conf.name ];
      })
    ));


    services.kea.dhcp4 = lib.attrsets.optionalAttrs (lib.length cfgSetDhcpServerInterfaceOnly > 0) {
      enable = true;
      settings = {
        control-socket = {
            socket-type = "unix";
            socket-name = "/run/kea/kea4-ctrl-socket";
        };

        interfaces-config = {
          interfaces = lib.forEach cfgSetDhcpServerInterfaceOnly (dhcp_interface_conf: dhcp_interface_conf.interfaceName);

          # Handles network interfaces not being ready (because they are down)
          # Will retry every 5secs for 1 hour and
          # if it still does not work it will fail the service
          service-sockets-max-retries = 720;
          service-sockets-retry-wait-time = 5000; # 5secs
          service-sockets-require-all = true;
        };
        lease-database = {
          name = builtins.toString cfg.dhcp.server.leaseDatabase.name;
          persist = cfg.dhcp.server.leaseDatabase.persist;
          type = cfg.dhcp.server.leaseDatabase.type;
        };

        rebind-timer = cfg.dhcp.server.generalSettings.rebindTimer;
        renew-timer = cfg.dhcp.server.generalSettings.renewTimer;
        valid-lifetime = cfg.dhcp.server.generalSettings.validLifetime;

        loggers = [{
          name = "kea-dhcp4";
          output-options = [
            { output = "stdout";
              pattern = "%-5p [%c/T-%t] %m\n"; }
          ];
          severity = "DEBU";
        }];


        subnet4 = lib.forEach cfgSetDhcpServerInterfaceOnly (dhcp_interface_conf: let
            cidr = ipv4_fn.fromCidrString dhcp_interface_conf.dhcp.server.gateway;

            subnet = "${cidr.network}/${builtins.toString cidr.prefix}";

            dhcpFirstIP = if dhcp_interface_conf.dhcp.server.firstIP == null
              then ipv4_fn.increase {
                ip = cidr.network; by = 5; subnet = subnet;}
              else ipv4_fn.increase {
                ip = cidr.network;
                by = dhcp_interface_conf.dhcp.server.firstIP;
                subnet = subnet;};

            domainNames = dhcp_interface_conf.dhcp.server.domainName
              ++ cfg.dhcp.server.generalSettings.domainName;

          in {
            id = dhcp_interface_conf.dhcp.server.id;
            pools = [
              ( { pool = "${dhcpFirstIP} - ${cidr.maxAddr}";
                } // lib.attrsets.optionalAttrs dhcp_interface_conf.dhcp.server.reservations-only {
                  client-class = "KNOWN";
                }
              )
            ];

            subnet = subnet;
            interface = dhcp_interface_conf.interfaceName;

            option-data = [
              { # code = 6;
                name = "domain-name-servers";
                csv-format = true;
                data = cidr.minAddr;
              }
            ] ++ lib.lists.optional (dhcp_interface_conf.dhcp.server.default_route) { # code = 3;
              name = "routers";
              data = cidr.address;
            } ++ lib.lists.optional (dhcp_interface_conf.dhcp.server.classless-static-route) {
              # source (example): https://github.com/isc-projects/kea/blob/60222843a6b2c4e7a6c7d4e63f88d0dcfa0d5b97/doc/examples/kea4/all-options.json#L1322-L1328
              name = "classless-static-route";
              data =
                lib.strings.concatImapStringsSep
                ", "
                ( _pos: dhcp_server_interface_conf: let
                    tmp_cidr = ipv4_fn.fromCidrString dhcp_server_interface_conf.dhcp.server.gateway;
                    tmp_subnet = "${tmp_cidr.network}/${builtins.toString tmp_cidr.prefix}";
                  in
                    "${tmp_subnet} - ${cidr.address}"
                )
                ( lib.lists.filter
                  ( dhcp_server_interface_conf:
                    dhcp_server_interface_conf.dhcp.server.gateway != dhcp_interface_conf.dhcp.server.gateway
                  )
                  cfgSetDhcpServerInterfaceOnly
                )
              ;

            } ++ lib.lists.optional (lib.length domainNames > 0) {
              name = "domain-name";
              csv-format = true;
              data = lib.strings.concatMapStringsSep ", "
              (domain: lib.toLower domain)
              domainNames;
            };

            reservations = lib.mapAttrsToList ( mac: value:
              { hw-address =
                  if ( ipv4_fn.fnValidMacAddress mac )
                  then mac
                  else throw ''The attribute key "${mac}", for DHCP reservations, is not a valid MAC address'';
              } // lib.attrsets.optionalAttrs ( value.ip-address != null ) {
                ip-address = value.ip-address;
              }
            ) dhcp_interface_conf.dhcp.server.reservations;
        });
      };
    };


    services.ntp = lib.attrsets.optionalAttrs (lib.length cfgSetDhcpServerInterfaceOnly > 0) {
      enable = true;

      extraConfig = lib.strings.concatMapStringsSep "\n"
        (dhcp_interface_conf: let
            cidr = ipv4_fn.fromCidrString dhcp_interface_conf.dhcp.server.gateway;
          in
            "restrict ${cidr.network} mask ${cidr.netmask} nomodify notrap nopeer"
        )
        cfgSetDhcpServerInterfaceOnly;
    };

#     notnft = {
#     };

    environment.systemPackages = [ pkgs.nftables ];

    systemd.services.systemd-networkd.environment = { SYSTEMD_LOG_LEVEL = "debug"; };

    services.pimd = lib.attrsets.optionalAttrs
      ( lib.lists.any (interface: interface.multicast) allInterfaces )
      {
        enable = true;
        settings.interfaces = lib.lists.forEach
          ( lib.lists.filter
            ( interface: lib.hasAttr "multicast" interface && interface.multicast )
            allInterfaces
          )
          ( interface: interface.name )
        ;
      };

    services.resolved = {
      enable = true;
      extraConfig = ''
        DNSStubListenerExtra=0.0.0.0
        MulticastDNS=no
      '';
    };

    networking = lib.optionalAttrs (lib.length cfgConfigInterface > 0) {
      useDHCP = lib.mkDefault false;

      useNetworkd = true;

      networkmanager.enable = lib.mkDefault false;
      networkmanager.unmanaged = ( lib.lists.flatten
        ( lib.lists.forEach
          cfgConfigInterface
          ( interface_conf:
            ( lib.lists.optional
              ( interface_conf.excludeFromNetworkManager || interface_conf.dhcp != null )
              interface_conf.name
            )
            ++
            lib.lists.forEach interface_conf.vlans (vlan_conf: vlanName vlan_conf)
          )
        )
      );

      firewall.enable = lib.mkForce false;

      nftables = {
        enable = true;
      } // (
        if (lib.pathExists ./netfilter.ruleset)
        then { rulesetFile = ./netfilter.ruleset; }
        else {
#           checkRuleset = false;
          tables."masquerade-ip-address" = {
            enable = true;
            family = "ip";
            content = let

              ip_masquerade_interfaces =
                lib.lists.filter
                ( interface_conf:
                  interface_conf.name == cfgDefaultRouteInterface ||
                  ( lib.hasAttr "ipMasquerade" interface_conf && interface_conf.ipMasquerade == true )
                )
                allInterfaces
              ;

            in /*lib.debug.traceValSeq*/ (
              lib.strings.concatMapStringsSep
              "\n"
              (x : if x == "" then "" else "  ${x}")
              (
                [ ""
                  "# Define the postrouting"
                  "chain postrouting {"
                  "  type nat hook postrouting priority 100; policy accept;"
                  "  # Masquerade rule: Replace with the IP of your default routing interface"
                ] ++
                ( lib.lists.forEach
                  ip_masquerade_interfaces
                  ( interface_conf: "  oifname ${interface_conf.name} masquerade" )
                ) ++
                [
                  "}"
                ]
              )
            );
          };
        }
      );
    };
  }
)
