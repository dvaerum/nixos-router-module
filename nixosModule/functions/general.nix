{ config
, pkgs
, lib
, ...
}:

rec {

  recursiveMerge = with lib; (attrList:
    let f = attrPath:
      zipAttrsWith (n: values:
        if tail values == []
          then head values
        else if all isList values
          then unique (concatLists values)
        else if all isAttrs values
          then f (attrPath ++ [n]) values
        else last values
      );
    in f [] attrList
  );



  ipv4_fn = import ./ipv4.nix {inherit pkgs lib;};

  cfg = config.my.router;
  cfgConfigInterface = cfg.configInterface;
  cfgConfigInterfacePath = "my.router.setInterface";
  cfgDefaultRouteInterface = cfg.defaultRouteInterface;

  cfgNetworkd = config.systemd.network;
  cfgNetworkdLinkPath = "systemd.network";

  # Moves all interfaces and vlans interfaces into one flatte list
  allInterfacesFn = interfaces: lib.lists.flatten (
    lib.lists.forEach
    interfaces
    ( interface_conf:
      [ interface_conf ]
      ++
      ( lib.lists.optional
        (lib.hasAttr "vlans" interface_conf)
        ( lib.lists.forEach
          interface_conf.vlans
          ( vlan_conf:
            vlan_conf // { name = vlanName vlan_conf; }
          )
        )
      )
      ++
      ( lib.lists.forEach
        interface_conf.bridges
        ( bridge_conf: bridge_conf )
      )
    )
  );
  allInterfaces = allInterfacesFn cfgConfigInterface;

  cfgSetDhcpServerInterfaceOnly = /*lib.debug.traceValSeq*/ (lib.lists.flatten (
    lib.lists.forEach
    (/*lib.debug.traceValSeq*/ cfgConfigInterface)
    ( interface_conf:
      ( lib.optionals
        ( interface_conf.dhcp != null && lib.hasAttr "server" interface_conf.dhcp )
        [{ interfaceName = interface_conf.name; dhcp = interface_conf.dhcp; }]
      )
      ++
      ( lib.map
        (vlan_conf: {interfaceName = vlanName vlan_conf; dhcp = vlan_conf.dhcp;})
        (builtins.filter (vlan_conf: vlan_conf.dhcp != null && lib.hasAttr "server" vlan_conf.dhcp) interface_conf.vlans)
      )
    )
  ));

  cfgSetDhcpServerInterfaceOnlyFilter = (fn: lib.lists.filter fn cfgSetDhcpServerInterfaceOnly);

  getInterfaceConf = (name: (
    lib.lists.findSingle
    (link_conf: link_conf.linkConfig.Name == name)
    (throw "No interfaces are configured to the name \"${name}\". Add the interface to the list \"${cfgConfigInterfacePath}\"")
    (throw "Too many. The interface name \"${name}\" is configured 2+ times. Check the list in \"${cfgConfigInterfacePath}\" and also \"${cfgNetworkdLinkPath}\". Debug info (${cfgNetworkdLinkPath}): ${builtins.toJSON cfgNetworkd.links}")
    (
      lib.attrsets.mapAttrsToList
      (filename: link_conf: link_conf // { _filename = filename;})
      cfgNetworkd.links
    )
  ));

  _checkIfInterfaceIsSet = (name: (
    if lib.length (getInterfaceConf name) == 1
    then name
    else throw "No interface configured with the name ${name}"
  ));

  systemdNetworkDHCP = (
    { interfaceName
    , interfaceConf
    }: let
      dhcp = interfaceConf.dhcp;

      selected_dhcp_config =
        if (dhcp == null)
        then null
        else if lib.lists.length (lib.attrsets.attrNames dhcp) == 1
        then /*lib.debug.traceValSeq*/ (lib.lists.last (lib.attrsets.attrNames dhcp))
        else throw ''
          You can only configure one attribure for `dhcp` section.
          Otherwise `dhcp` should be it default value: null
        ''
      ;

    in
      if selected_dhcp_config == null then
        { networkConfig = {
            LinkLocalAddressing="no";
          };
          linkConfig = {
              RequiredForOnline =
                if interfaceConf.requiredForOnline == null
                then false
                else interfaceConf.requiredForOnline
              ;
          };
        }

      else {
        static = let
          cidr = ipv4_fn.fromCidrString dhcp.static.ip-address;
        in {
          networkConfig = {
            LinkLocalAddressing="no";
            IPv4Forwarding = interfaceConf.forwarding;

            Address = "${cidr.address}/${builtins.toString cidr.prefix}";
          } // lib.attrsets.optionalAttrs (lib.lists.length dhcp.static.dns-servers > 0) {
            DNS = dhcp.static.dns-servers;
          };

          linkConfig = {
            RequiredForOnline =
              if interfaceConf.requiredForOnline == null
              then false
              else interfaceConf.requiredForOnline
            ;
          };
        };

        client = {
          networkConfig = {
            DHCP = "ipv4";
            IPv4Forwarding = interfaceConf.forwarding;
            LinkLocalAddressing="no";
          };

          dhcpV4Config = {
            UseRoutes = if cfgDefaultRouteInterface == interfaceName then true else false;
            ClientIdentifier = "mac";
          };
          linkConfig = {
            RequiredForOnline =
              if interfaceConf.requiredForOnline == null
              then false
              else interfaceConf.requiredForOnline
            ;
          };
        };

        server = let
          cidr = ipv4_fn.fromCidrString dhcp.server.gateway;
        in {
          networkConfig = {
            Address = "${cidr.address}/${builtins.toString cidr.prefix}";
            IPv4Forwarding = interfaceConf.forwarding;

            LinkLocalAddressing="no";
          };

          linkConfig = {
            RequiredForOnline =
              if interfaceConf.requiredForOnline == null
              then true
              else interfaceConf.requiredForOnline
            ;
          };
        };
      }.${selected_dhcp_config}
      //
      { routes = lib.lists.forEach interfaceConf.staticRoutes ( static_route:
          { Gateway = (
              if selected_dhcp_config == "static"
              then (
                if dhcp.static.gateway == null
                then throw ''
                  The `dhcp.${selected_dhcp_config}.gateway` needs to be configured otherwise
                  `staticRoutes` cannot be configured.
                ''
                else dhcp.static.gateway
              )

              else if selected_dhcp_config == "client"
              then "_dhcp4"

              else if selected_dhcp_config == "server"
              then (ipv4_fn.fromCidrString dhcp.server.gateway).address

              else throw "The `dhcp.${selected_dhcp_config}` config is not supported with `static_route`"
            );
            Destination = static_route;
          }
        );
      }
    )
  ;

  interfaceFilename = (name: "10-${name}");
  vlanName = (vlan_conf: if vlan_conf.name == null
                         then "vlan-${lib.strings.fixedWidthNumber 4 vlan_conf.id}"
                         else vlan_conf.name);
  vlanFilename = (vlan_conf: "20-${vlanName (vlan_conf // {name = null; })}");
  bridgeFilename = (bridge_conf: "20-${bridge_conf.name}");
}
