## _module\.args

Additional arguments passed to each module in addition to ones
like ` lib `, ` config `,
and ` pkgs `, ` modulesPath `\.

This option is also available to all submodules\. Submodules do not
inherit args from their parent module, nor do they provide args to
their parent module or sibling submodules\. The sole exception to
this is the argument ` name ` which is provided by
parent modules to a submodule and contains the attribute name
the submodule is bound to, or a unique generated name if it is
not bound to an attribute\.

Some arguments are already passed by default, of which the
following *cannot* be changed with this option:

 - ` lib `: The nixpkgs library\.

 - ` config `: The results of all options after merging the values from all modules together\.

 - ` options `: The options declared in all modules\.

 - ` specialArgs `: The ` specialArgs ` argument passed to ` evalModules `\.

 - All attributes of ` specialArgs `
   
   Whereas option values can generally depend on other option values
   thanks to laziness, this does not apply to ` imports `, which
   must be computed statically before anything else\.
   
   For this reason, callers of the module system can provide ` specialArgs `
   which are available during import resolution\.
   
   For NixOS, ` specialArgs ` includes
   ` modulesPath `, which allows you to import
   extra modules from the nixpkgs package tree without having to
   somehow make the module aware of the location of the
   ` nixpkgs ` or NixOS directories\.
   
   ```
   { modulesPath, ... }: {
     imports = [
       (modulesPath + "/profiles/minimal.nix")
     ];
   }
   ```

For NixOS, the default value for this option includes at least this argument:

 - ` pkgs `: The nixpkgs package set according to
   the ` nixpkgs.pkgs ` option\.



*Type:*
lazy attribute set of raw value



*Default:*

```nix
{ }
```

*Declared by:*
 - [\<nixpkgs/lib/modules\.nix>](https://github.com/NixOS/nixpkgs/blob//lib/modules.nix)



## my\.router\.enable



Enable Router module



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces



Config all bridge interfaces



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  br0 = {
    dhcp = {
      client = true;
    };
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp



Select if this network interface should be configured for DHCP Server or Client\.
It is also possible to just assign a static IP\.



*Type:*
null or attribute-tagged union with choices: client, server, static



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.client



To-do: make description



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server



To-do: make description



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.address



The router’s own host IP on this subnet, in CIDR notation
(e\.g\. ` 192.168.1.1/24 `, not ` 192.168.1.0/24 `)\. Sets the
interface’s IP and the DHCP subnet, and is the value ` gateway `
and ` dns-servers ` fall back to when left unset\.



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.1/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.classless-static-route



Expose all other subnets, declared as a ` dhcp.server.address `,
as a classless static route (Option: 121)\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.default-route



Whether to advertise a default route\. ` false ` sends no
` gateway `, so clients get no default route\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.dns-server\.enable



Enable the DNS Server (Unbound) for this network interface\.

Only takes effect when ` my.router.dns-server.enable ` is
also ` true ` — this is a per-interface opt-out, not an
independent switch\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.dns-server\.trust



Controls how DNS requests from this interface’s subnet are
treated:

 - ` lan ` (the default): the interface’s own DNS-derived
   records (reservations, DHCP pool leases) are published,
   and ` my.router.dns-server.spoof ` rules are enforced\.
 - ` forward-only `: requests are still resolved/forwarded,
   but no spoof rules are applied and no local records are
   published for this subnet\. Intended for a trusted peer
   network (e\.g\. a sibling router reached over a VXLAN
   tunnel) that should be able to use this router as a
   resolver without inheriting its spoof policy\.



*Type:*
one of “lan”, “forward-only”



*Default:*

```nix
"lan"
```



*Example:*

```nix
"forward-only"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.dns-servers



The DNS server(s) advertised to DHCP clients (kea
` domain-name-servers `):

 - ` null ` (the default): advertise this router’s own ` address `\.
 - ` [ ] `: advertise no DNS server at all\.
 - a non-empty list: advertise exactly those servers\.



*Type:*
null or (list of (IP address))



*Default:*

```nix
null
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.firstIP



Set the first IP address provides by the DHCP Server\.
Example: ` 10 ` for subnet ` 192.168.1.0/24 `
will be calculated to ` 192.168.1.10 `\.



*Type:*
signed integer



*Default:*

```nix
5
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.gateway



Default route advertised to clients (kea ` routers `):

 - ` null ` (the default): this router’s own ` address `\.
 - an IP: advertise that address instead of this router\.
   Only sent when ` default-route ` is true\.



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.254"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.id



Subnet IDs must be greater than zero and less than 4294967295



*Type:*
integer between 1 and 4294967294 (both inclusive)



*Default:*

```nix
1024
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.enable



Enable PXE Boot support for this network interface\.

Side effect — DHCP client matching becomes MAC-only on this
subnet: enabling PXE boot sets kea’s ` match-client-id = false `
for the whole subnet, so ALL clients on it (pool and reserved)
are identified by MAC address only, and the DHCP client-id /
DUID is ignored\.

Why: UEFI PXE firmware, the OS installer and the installed OS
present DIFFERENT DUID-derived client-ids for the SAME MAC\. With
kea’s default (client-id matching) a stale lease taken during
PXE/install blocks the installed OS from reclaiming its RESERVED
IP (it falls back to a pool address and needs a manual lease
drop)\. MAC-only matching makes a fixed reservation survive
firmware -> installer -> installed OS\.

Trade-off: because it is subnet-wide, non-PXE hosts on this
subnet also lose client-id features (a NIC swap yields a new
identity/lease; a single MAC cannot host multiple logical DHCP
clients)\. Use a dedicated subnet for PXE provisioning if that
matters\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.defaultIso



Select which ISO file should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"rhel-9.6-x86_64-dvd.iso"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.defaultScriptName



Select which autoinstall script should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"minimal-environment.kstart"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.reservations



Make reservations (MAC address specific configurations)\.
Example: Make it so that one IP address is always provided to
the selected MAC address\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  "00:11:22:33:44:55" = {
    hostname = "nas";
    ip-address = "192.168.1.2";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.hostname



DNS hostname for this reservation\.

When set, ` dns-server.enable ` (this router’s, not
just this interface’s) publishes it as an A record
via the DHCP-lease hook – always taking priority
over anything the client itself requests over DHCP,
regardless of ` dns-server.publish-leases.enable `\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"nas"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.ip-address



Bind the IP address the MAC address (attribute key)



*Type:*
null or (IP address)



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.reservations-only



Only reply to the client which matches the information in ` dhcp.server.reservations `\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.static



To-do: make description (Note static IP is put here, but there may be a better location in the structure)



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.static\.dns-servers



Set the IP address(es) of the dns-server(s)



*Type:*
list of (IP address)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.static\.gateway



Set the IP address of the gateway



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.static\.ip-address



```
            Set the ip and subnet in the CIDR format.
```



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.10/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.excludeFromNetworkManager



Ensure that the interface is excluded from NetworkManager



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.forwarding



IPv4 forwarding\. It is turn on by default\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.ipMasquerade



Enable ip masquerade (aka NAT) on the interface\.

This is needed e\.g\. if the interface is the WAN interface\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.multicast



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.name



Set the name of the network interface



*Type:*
Network Interface Name ()

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.requiredForOnline



When configured to ` null ` (which is the default)\.

 - requiredForOnline will be set to ` true `
   if the interface is configured as ` dhcp.server `\.

 - requiredForOnline will be set to ` false `
   if the interface is configured as ` dhcp.client ` or ` dhcp.static `\.

This behavior can be overwritten by configuring this option to ` true ` and
the ` systemd-networkd-wait-online.service ` will
wait for this interface to be configured (until timeout)\.
Or set the option to ` false ` for the ` systemd-networkd-wait-online.service `
to ignore this interface\.



*Type:*
null or boolean



*Default:*

```nix
null
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.staticRoutes



Added static routes for the interface\.

In the case of ` dhcp.static `,
if the route should be configured as the default use ` 0.0.0.0/0 `\.



*Type:*
list of (Subnet)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "172.20.90.0/24"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface



Config all physical/plain network interfaces



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  eth1 = {
    dhcp = {
      static = {
        ip-address = "10.0.1.2/24";
      };
    };
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.bridges



Creating a bridge interface with and include this interface in the bridge\.



*Type:*
list of (submodule)



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.bridges\.\*\.name



Select the name of the bridge interface



*Type:*
null or (Network Interface Name ())



*Default:*

```nix
null
```



*Example:*

```nix
"br0"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp



Select if this network interface should be configured for DHCP Server or Client\.
It is also possible to just assign a static IP\.



*Type:*
null or attribute-tagged union with choices: client, server, static



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.client



To-do: make description



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server



To-do: make description



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.address



The router’s own host IP on this subnet, in CIDR notation
(e\.g\. ` 192.168.1.1/24 `, not ` 192.168.1.0/24 `)\. Sets the
interface’s IP and the DHCP subnet, and is the value ` gateway `
and ` dns-servers ` fall back to when left unset\.



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.1/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.classless-static-route



Expose all other subnets, declared as a ` dhcp.server.address `,
as a classless static route (Option: 121)\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.default-route



Whether to advertise a default route\. ` false ` sends no
` gateway `, so clients get no default route\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.dns-server\.enable



Enable the DNS Server (Unbound) for this network interface\.

Only takes effect when ` my.router.dns-server.enable ` is
also ` true ` — this is a per-interface opt-out, not an
independent switch\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.dns-server\.trust



Controls how DNS requests from this interface’s subnet are
treated:

 - ` lan ` (the default): the interface’s own DNS-derived
   records (reservations, DHCP pool leases) are published,
   and ` my.router.dns-server.spoof ` rules are enforced\.
 - ` forward-only `: requests are still resolved/forwarded,
   but no spoof rules are applied and no local records are
   published for this subnet\. Intended for a trusted peer
   network (e\.g\. a sibling router reached over a VXLAN
   tunnel) that should be able to use this router as a
   resolver without inheriting its spoof policy\.



*Type:*
one of “lan”, “forward-only”



*Default:*

```nix
"lan"
```



*Example:*

```nix
"forward-only"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.dns-servers



The DNS server(s) advertised to DHCP clients (kea
` domain-name-servers `):

 - ` null ` (the default): advertise this router’s own ` address `\.
 - ` [ ] `: advertise no DNS server at all\.
 - a non-empty list: advertise exactly those servers\.



*Type:*
null or (list of (IP address))



*Default:*

```nix
null
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.firstIP



Set the first IP address provides by the DHCP Server\.
Example: ` 10 ` for subnet ` 192.168.1.0/24 `
will be calculated to ` 192.168.1.10 `\.



*Type:*
signed integer



*Default:*

```nix
5
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.gateway



Default route advertised to clients (kea ` routers `):

 - ` null ` (the default): this router’s own ` address `\.
 - an IP: advertise that address instead of this router\.
   Only sent when ` default-route ` is true\.



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.254"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.id



Subnet IDs must be greater than zero and less than 4294967295



*Type:*
integer between 1 and 4294967294 (both inclusive)



*Default:*

```nix
1024
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.pxe-boot\.enable



Enable PXE Boot support for this network interface\.

Side effect — DHCP client matching becomes MAC-only on this
subnet: enabling PXE boot sets kea’s ` match-client-id = false `
for the whole subnet, so ALL clients on it (pool and reserved)
are identified by MAC address only, and the DHCP client-id /
DUID is ignored\.

Why: UEFI PXE firmware, the OS installer and the installed OS
present DIFFERENT DUID-derived client-ids for the SAME MAC\. With
kea’s default (client-id matching) a stale lease taken during
PXE/install blocks the installed OS from reclaiming its RESERVED
IP (it falls back to a pool address and needs a manual lease
drop)\. MAC-only matching makes a fixed reservation survive
firmware -> installer -> installed OS\.

Trade-off: because it is subnet-wide, non-PXE hosts on this
subnet also lose client-id features (a NIC swap yields a new
identity/lease; a single MAC cannot host multiple logical DHCP
clients)\. Use a dedicated subnet for PXE provisioning if that
matters\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.pxe-boot\.defaultIso



Select which ISO file should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"rhel-9.6-x86_64-dvd.iso"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.pxe-boot\.defaultScriptName



Select which autoinstall script should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"minimal-environment.kstart"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.reservations



Make reservations (MAC address specific configurations)\.
Example: Make it so that one IP address is always provided to
the selected MAC address\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  "00:11:22:33:44:55" = {
    hostname = "nas";
    ip-address = "192.168.1.2";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.reservations\.\<name>\.hostname



DNS hostname for this reservation\.

When set, ` dns-server.enable ` (this router’s, not
just this interface’s) publishes it as an A record
via the DHCP-lease hook – always taking priority
over anything the client itself requests over DHCP,
regardless of ` dns-server.publish-leases.enable `\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"nas"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.reservations\.\<name>\.ip-address



Bind the IP address the MAC address (attribute key)



*Type:*
null or (IP address)



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.reservations-only



Only reply to the client which matches the information in ` dhcp.server.reservations `\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.static



To-do: make description (Note static IP is put here, but there may be a better location in the structure)



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.static\.dns-servers



Set the IP address(es) of the dns-server(s)



*Type:*
list of (IP address)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.static\.gateway



Set the IP address of the gateway



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.static\.ip-address



```
            Set the ip and subnet in the CIDR format.
```



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.10/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.excludeFromNetworkManager



Ensure that the interface is excluded from NetworkManager



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.forwarding



IPv4 forwarding\. It is turn on by default\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.ipMasquerade



Enable ip masquerade (aka NAT) on the interface\.

This is needed e\.g\. if the interface is the WAN interface\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.linkConfig



Alias for ` systemd.network.links.<name>.linkConfig `\.

Basically live copy-paste of the NixOS ` options ` for this systemd setting\.



*Type:*
attribute set



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.mac



MAC address of the network interface\.

It can be either a MAC-address or list of MAC-addresses\.

**Example:** A list of MAC-addresses can make sense if you have multiple
USB adapter which are not connected at the same time, but you want to have
the same network interface name (and want to be configured the same)



*Type:*
null or (list of (Mac Address (use \`:\` or \`-\` as separator))) or (Mac Address (use \`:\` or \`-\` as separator))



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.multicast



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.name



Set the name of the network interface



*Type:*
Network Interface Name ()

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.requiredForOnline



When configured to ` null ` (which is the default)\.

 - requiredForOnline will be set to ` true `
   if the interface is configured as ` dhcp.server `\.

 - requiredForOnline will be set to ` false `
   if the interface is configured as ` dhcp.client ` or ` dhcp.static `\.

This behavior can be overwritten by configuring this option to ` true ` and
the ` systemd-networkd-wait-online.service ` will
wait for this interface to be configured (until timeout)\.
Or set the option to ` false ` for the ` systemd-networkd-wait-online.service `
to ignore this interface\.



*Type:*
null or boolean



*Default:*

```nix
null
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.staticRoutes



Added static routes for the interface\.

In the case of ` dhcp.static `,
if the route should be configured as the default use ` 0.0.0.0/0 `\.



*Type:*
list of (Subnet)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "172.20.90.0/24"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans



Create a interface to handle VLAN tagged packages recieved on this interface\.



*Type:*
list of (submodule)



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.bridges



Creating a bridge interface with and include this interface in the bridge\.



*Type:*
list of (submodule)



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.bridges\.\*\.name



Select the name of the bridge interface



*Type:*
null or (Network Interface Name ())



*Default:*

```nix
null
```



*Example:*

```nix
"br0"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp



Select if this network interface should be configured for DHCP Server or Client\.
It is also possible to just assign a static IP\.



*Type:*
null or attribute-tagged union with choices: client, server, static



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.client



To-do: make description



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server



To-do: make description



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.address



The router’s own host IP on this subnet, in CIDR notation
(e\.g\. ` 192.168.1.1/24 `, not ` 192.168.1.0/24 `)\. Sets the
interface’s IP and the DHCP subnet, and is the value ` gateway `
and ` dns-servers ` fall back to when left unset\.



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.1/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.classless-static-route



Expose all other subnets, declared as a ` dhcp.server.address `,
as a classless static route (Option: 121)\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.default-route



Whether to advertise a default route\. ` false ` sends no
` gateway `, so clients get no default route\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.dns-server\.enable



Enable the DNS Server (Unbound) for this network interface\.

Only takes effect when ` my.router.dns-server.enable ` is
also ` true ` — this is a per-interface opt-out, not an
independent switch\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.dns-server\.trust



Controls how DNS requests from this interface’s subnet are
treated:

 - ` lan ` (the default): the interface’s own DNS-derived
   records (reservations, DHCP pool leases) are published,
   and ` my.router.dns-server.spoof ` rules are enforced\.
 - ` forward-only `: requests are still resolved/forwarded,
   but no spoof rules are applied and no local records are
   published for this subnet\. Intended for a trusted peer
   network (e\.g\. a sibling router reached over a VXLAN
   tunnel) that should be able to use this router as a
   resolver without inheriting its spoof policy\.



*Type:*
one of “lan”, “forward-only”



*Default:*

```nix
"lan"
```



*Example:*

```nix
"forward-only"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.dns-servers



The DNS server(s) advertised to DHCP clients (kea
` domain-name-servers `):

 - ` null ` (the default): advertise this router’s own ` address `\.
 - ` [ ] `: advertise no DNS server at all\.
 - a non-empty list: advertise exactly those servers\.



*Type:*
null or (list of (IP address))



*Default:*

```nix
null
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.firstIP



Set the first IP address provides by the DHCP Server\.
Example: ` 10 ` for subnet ` 192.168.1.0/24 `
will be calculated to ` 192.168.1.10 `\.



*Type:*
signed integer



*Default:*

```nix
5
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.gateway



Default route advertised to clients (kea ` routers `):

 - ` null ` (the default): this router’s own ` address `\.
 - an IP: advertise that address instead of this router\.
   Only sent when ` default-route ` is true\.



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.254"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.id



Subnet IDs must be greater than zero and less than 4294967295



*Type:*
integer between 1 and 4294967294 (both inclusive)



*Default:*

```nix
1024
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.pxe-boot\.enable



Enable PXE Boot support for this network interface\.

Side effect — DHCP client matching becomes MAC-only on this
subnet: enabling PXE boot sets kea’s ` match-client-id = false `
for the whole subnet, so ALL clients on it (pool and reserved)
are identified by MAC address only, and the DHCP client-id /
DUID is ignored\.

Why: UEFI PXE firmware, the OS installer and the installed OS
present DIFFERENT DUID-derived client-ids for the SAME MAC\. With
kea’s default (client-id matching) a stale lease taken during
PXE/install blocks the installed OS from reclaiming its RESERVED
IP (it falls back to a pool address and needs a manual lease
drop)\. MAC-only matching makes a fixed reservation survive
firmware -> installer -> installed OS\.

Trade-off: because it is subnet-wide, non-PXE hosts on this
subnet also lose client-id features (a NIC swap yields a new
identity/lease; a single MAC cannot host multiple logical DHCP
clients)\. Use a dedicated subnet for PXE provisioning if that
matters\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.pxe-boot\.defaultIso



Select which ISO file should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"rhel-9.6-x86_64-dvd.iso"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.pxe-boot\.defaultScriptName



Select which autoinstall script should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"minimal-environment.kstart"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.reservations



Make reservations (MAC address specific configurations)\.
Example: Make it so that one IP address is always provided to
the selected MAC address\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  "00:11:22:33:44:55" = {
    hostname = "nas";
    ip-address = "192.168.1.2";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.reservations\.\<name>\.hostname



DNS hostname for this reservation\.

When set, ` dns-server.enable ` (this router’s, not
just this interface’s) publishes it as an A record
via the DHCP-lease hook – always taking priority
over anything the client itself requests over DHCP,
regardless of ` dns-server.publish-leases.enable `\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"nas"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.reservations\.\<name>\.ip-address



Bind the IP address the MAC address (attribute key)



*Type:*
null or (IP address)



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.reservations-only



Only reply to the client which matches the information in ` dhcp.server.reservations `\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.static



To-do: make description (Note static IP is put here, but there may be a better location in the structure)



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.static\.dns-servers



Set the IP address(es) of the dns-server(s)



*Type:*
list of (IP address)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.static\.gateway



Set the IP address of the gateway



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.static\.ip-address



```
            Set the ip and subnet in the CIDR format.
```



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.10/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.excludeFromNetworkManager



Ensure that the interface is excluded from NetworkManager



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.forwarding



IPv4 forwarding\. It is turn on by default\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.id



Set VLan ID of the network interface



*Type:*
integer between 1 and 4096 (both inclusive)



*Example:*

```nix
1337
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.ipMasquerade



Enable ip masquerade (aka NAT) on the interface\.

This is needed e\.g\. if the interface is the WAN interface\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.multicast

*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.name



Option for setting the name of the VLAN
Otherwise it will get the default name: vlan-\<ID>



*Type:*
null or (Network Interface Name ())



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.requiredForOnline



When configured to ` null ` (which is the default)\.

 - requiredForOnline will be set to ` true `
   if the interface is configured as ` dhcp.server `\.

 - requiredForOnline will be set to ` false `
   if the interface is configured as ` dhcp.client ` or ` dhcp.static `\.

This behavior can be overwritten by configuring this option to ` true ` and
the ` systemd-networkd-wait-online.service ` will
wait for this interface to be configured (until timeout)\.
Or set the option to ` false ` for the ` systemd-networkd-wait-online.service `
to ignore this interface\.



*Type:*
null or boolean



*Default:*

```nix
null
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.staticRoutes



Added static routes for the interface\.

In the case of ` dhcp.static `,
if the route should be configured as the default use ` 0.0.0.0/0 `\.



*Type:*
list of (Subnet)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "172.20.90.0/24"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.defaultRouteInterface



Name of the network interface with the default route



*Type:*
Network Interface Name ()



*Default:*

```nix
"builtin-ether"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.defaultRouteMetric



Set the matric (priority) for the default route,
in case there are other services when also tries to config an default route\.



*Type:*
signed integer



*Default:*

```nix
75
```



*Example:*

```nix
100
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings



Config



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.rebindTimer



Set rebind time (seconds)



*Type:*
signed integer



*Default:*

```nix
2000
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.renewTimer



Set renew time (seconds)



*Type:*
signed integer



*Default:*

```nix
1000
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.validLifetime



Set valid lifetime (seconds)



*Type:*
signed integer



*Default:*

```nix
4000
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.hooksLibraries



Kea DHCPv4 hook libraries to load\.



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.hooksLibraries\.run_script



Kea DHCPv4 ` run_script ` hook instances – each entry calls
` path ` as ` <path> <hook-point-name> ` for every Kea DHCPv4
hook point listed in ` triggers `, with lease/query data
passed via environment variables Kea itself sets
(` LEASE4_* `, ` QUERY4_* `, …; see the Kea ARM’s Run Script
hook chapter for the full list per hook point)\.

Keyed by an arbitrary name, not a fixed field, so more
than one contributor – this module’s own DNS-lease
publishing, plus anything else in your own configuration
– can each register an entry without conflicting\.

Unlike most Kea hooks, ` run_script ` cannot actually be
loaded more than once: Kea logs a second ` hooks-libraries `
entry pointing at the same hook as “loaded” independently,
but at runtime only the LAST one configured ever actually
fires\. So every entry here shares a single generated
dispatcher script and a single real Kea ` hooks-libraries `
entry; ` triggers ` is how each one still only reacts to the
hook points it cares about\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  my-hook = {
    path = "/path/to/script.sh";
    triggers = [
      "lease4_release"
    ];
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.hooksLibraries\.run_script\.\<name>\.environment



Extra environment variables to set for ` path `\. Kea
itself never passes anything to a run_script beyond
the hook-point name, so this is how you get static
configuration into your script without writing your
own wrapper\.



*Type:*
attribute set of string



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.hooksLibraries\.run_script\.\<name>\.path



Path to the script to invoke\.



*Type:*
string

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.hooksLibraries\.run_script\.\<name>\.triggers



Which Kea DHCPv4 hook points to invoke ` path ` for\.



*Type:*
list of (one of “leases4_committed”, “lease4_expire”, “lease4_release”, “lease4_renew”, “lease4_recover”, “lease4_decline”)



*Default:*

```nix
[
  "leases4_committed"
  "lease4_expire"
  "lease4_release"
  "lease4_renew"
  "lease4_recover"
  "lease4_decline"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase



Specify the type of lease database



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase\.name



Set location for database lease file



*Type:*
absolute path



*Default:*

```nix
/var/lib/kea/dhcp4.leases
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase\.persist



Should the leases stored in the lease-file be persistent



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase\.type



Only the ` memfile ` option is available



*Type:*
value “memfile” (singular enum)



*Default:*

```nix
"memfile"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dns-server\.enable



Enable the DNS Server (Unbound)\.

When enabled, every ` dhcp.server ` interface gets its own DNS
service, bound directly to that interface’s own address (never
` 0.0.0.0 `), unless that interface’s own
` dhcp.server.dns-server.enable ` is set to ` false `\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dns-server\.publish-leases\.enable



Also publish an A record for dynamic (non-reserved) DHCP
pool leases, using the hostname the client itself sends
over DHCP (option 12) – sanitized by Kea
(` hostname-char-set `), and rejected outright if it collides
with any reservation’s ` hostname ` or ` dns-server.spoof.overrides `
entry\.

Off by default: unlike a reservation’s ` hostname ` (admin-
authored), a pool client’s hostname is unauthenticated
input from whatever device asks for an address – turning
this on means trusting that input enough to serve it back
as a real DNS answer on the LAN\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dns-server\.spoof\.blocklist\.enable



Enable ad/tracker DNS blocking via a periodically-fetched
RPZ zone, built from the hosts-file-format lists in ` urls `\.
Applied on every interface with
` dhcp.server.dns-server.trust = "lan" `\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dns-server\.spoof\.blocklist\.updateInterval



systemd ` OnCalendar ` spec for how often the blocklist is
re-fetched\.



*Type:*
string



*Default:*

```nix
"daily"
```



*Example:*

```nix
"hourly"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dns-server\.spoof\.blocklist\.urls



hosts-file-format blocklist URLs (e\.g\. StevenBlack/hosts,
oisd)\. Fetched and converted to an RPZ zonefile on the
schedule set by ` updateInterval `; the fetch is a runtime
network call, not pinned/reproducible like the rest of this
module\.



*Type:*
list of string



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dns-server\.spoof\.overrides



Per-hostname DNS overrides (split-horizon redirects), applied
via RPZ local-data\. These always take priority over the real
answer, on every interface with ` dhcp.server.dns-server.trust = "lan" ` (the default)\.



*Type:*
attribute set of ((list of (IP address)) or (IP address) convertible to it)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  "nas.home.arpa" = [
    "10.0.0.5"
    "10.0.0.6"
  ];
  "printer.home.arpa" = "10.0.0.9";
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.enable



Enable support for PXE Boot\.

This will download PXE boot binaries and
prepare supported Linux distrobutions for download\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.autoinstall



Configure autoinstall script for the different ISOs



*Type:*
attribute set of list of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  "rhel-9.6-x86_64-dvd.iso" = {
    script = /home/runner/work/nixos-router-module/nixos-router-module/nixosModule/path/to/script.kstart;
    scriptName = "minimal-environment.kstart";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.autoinstall\.\<name>\.\*\.script



Provide the content of the script or the path to the script



*Type:*
absolute path or string



*Example:*

```nix
/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/path/to/script.kstart
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.autoinstall\.\<name>\.\*\.scriptName



Name of the script in the GRUB Menu\.



*Type:*
string



*Example:*

```nix
"minimal-environment.kstart"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.isoFolderPath



Path to the folder which contains the iso files\.



*Type:*
absolute path



*Example:*

```nix
"/data/iso"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces



Config all VXLAN (unicast point-to-point) interfaces



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  vxlan1000 = {
    dhcp = {
      static = {
        ip-address = "10.100.0.2/30";
      };
    };
    remote = "172.20.1.1";
    vni = 1000;
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.bridges



Creating a bridge interface with and include this interface in the bridge\.



*Type:*
list of (submodule)



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.bridges\.\*\.name



Select the name of the bridge interface



*Type:*
null or (Network Interface Name ())



*Default:*

```nix
null
```



*Example:*

```nix
"br0"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.destinationPort



UDP port used for the encapsulated traffic\. Defaults to the
IANA-assigned standard (4789) rather than the Linux kernel’s own
historical non-standard default (8472), for interop with
non-Linux VXLAN peers\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
4789
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp



Select if this network interface should be configured for DHCP Server or Client\.
It is also possible to just assign a static IP\.



*Type:*
null or attribute-tagged union with choices: client, server, static



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.client



To-do: make description



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server



To-do: make description



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.address



The router’s own host IP on this subnet, in CIDR notation
(e\.g\. ` 192.168.1.1/24 `, not ` 192.168.1.0/24 `)\. Sets the
interface’s IP and the DHCP subnet, and is the value ` gateway `
and ` dns-servers ` fall back to when left unset\.



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.1/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.classless-static-route



Expose all other subnets, declared as a ` dhcp.server.address `,
as a classless static route (Option: 121)\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.default-route



Whether to advertise a default route\. ` false ` sends no
` gateway `, so clients get no default route\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.dns-server\.enable



Enable the DNS Server (Unbound) for this network interface\.

Only takes effect when ` my.router.dns-server.enable ` is
also ` true ` — this is a per-interface opt-out, not an
independent switch\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.dns-server\.trust



Controls how DNS requests from this interface’s subnet are
treated:

 - ` lan ` (the default): the interface’s own DNS-derived
   records (reservations, DHCP pool leases) are published,
   and ` my.router.dns-server.spoof ` rules are enforced\.
 - ` forward-only `: requests are still resolved/forwarded,
   but no spoof rules are applied and no local records are
   published for this subnet\. Intended for a trusted peer
   network (e\.g\. a sibling router reached over a VXLAN
   tunnel) that should be able to use this router as a
   resolver without inheriting its spoof policy\.



*Type:*
one of “lan”, “forward-only”



*Default:*

```nix
"lan"
```



*Example:*

```nix
"forward-only"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.dns-servers



The DNS server(s) advertised to DHCP clients (kea
` domain-name-servers `):

 - ` null ` (the default): advertise this router’s own ` address `\.
 - ` [ ] `: advertise no DNS server at all\.
 - a non-empty list: advertise exactly those servers\.



*Type:*
null or (list of (IP address))



*Default:*

```nix
null
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.firstIP



Set the first IP address provides by the DHCP Server\.
Example: ` 10 ` for subnet ` 192.168.1.0/24 `
will be calculated to ` 192.168.1.10 `\.



*Type:*
signed integer



*Default:*

```nix
5
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.gateway



Default route advertised to clients (kea ` routers `):

 - ` null ` (the default): this router’s own ` address `\.
 - an IP: advertise that address instead of this router\.
   Only sent when ` default-route ` is true\.



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.254"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.id



Subnet IDs must be greater than zero and less than 4294967295



*Type:*
integer between 1 and 4294967294 (both inclusive)



*Default:*

```nix
1024
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.enable



Enable PXE Boot support for this network interface\.

Side effect — DHCP client matching becomes MAC-only on this
subnet: enabling PXE boot sets kea’s ` match-client-id = false `
for the whole subnet, so ALL clients on it (pool and reserved)
are identified by MAC address only, and the DHCP client-id /
DUID is ignored\.

Why: UEFI PXE firmware, the OS installer and the installed OS
present DIFFERENT DUID-derived client-ids for the SAME MAC\. With
kea’s default (client-id matching) a stale lease taken during
PXE/install blocks the installed OS from reclaiming its RESERVED
IP (it falls back to a pool address and needs a manual lease
drop)\. MAC-only matching makes a fixed reservation survive
firmware -> installer -> installed OS\.

Trade-off: because it is subnet-wide, non-PXE hosts on this
subnet also lose client-id features (a NIC swap yields a new
identity/lease; a single MAC cannot host multiple logical DHCP
clients)\. Use a dedicated subnet for PXE provisioning if that
matters\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.defaultIso



Select which ISO file should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"rhel-9.6-x86_64-dvd.iso"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.defaultScriptName



Select which autoinstall script should be selected by default\.



*Type:*
string



*Default:*

```nix
""
```



*Example:*

```nix
"minimal-environment.kstart"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.reservations



Make reservations (MAC address specific configurations)\.
Example: Make it so that one IP address is always provided to
the selected MAC address\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  "00:11:22:33:44:55" = {
    hostname = "nas";
    ip-address = "192.168.1.2";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.hostname



DNS hostname for this reservation\.

When set, ` dns-server.enable ` (this router’s, not
just this interface’s) publishes it as an A record
via the DHCP-lease hook – always taking priority
over anything the client itself requests over DHCP,
regardless of ` dns-server.publish-leases.enable `\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"nas"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.ip-address



Bind the IP address the MAC address (attribute key)



*Type:*
null or (IP address)



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.reservations-only



Only reply to the client which matches the information in ` dhcp.server.reservations `\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.static



To-do: make description (Note static IP is put here, but there may be a better location in the structure)



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.static\.dns-servers



Set the IP address(es) of the dns-server(s)



*Type:*
list of (IP address)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "192.168.1.1"
  "1.1.1.1"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.static\.gateway



Set the IP address of the gateway



*Type:*
null or (IP address)



*Default:*

```nix
null
```



*Example:*

```nix
"192.168.1.1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.static\.ip-address



```
            Set the ip and subnet in the CIDR format.
```



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*

```nix
"192.168.1.10/24"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.excludeFromNetworkManager



Ensure that the interface is excluded from NetworkManager



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.forwarding



IPv4 forwarding\. It is turn on by default\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.ipMasquerade



Enable ip masquerade (aka NAT) on the interface\.

This is needed e\.g\. if the interface is the WAN interface\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.local



Source IP to bind/send from\. ` null ` (the default) lets the kernel
pick whatever address the routing table would use to reach
` remote `\.



*Type:*
null or (IP address)



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.multicast



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.name



Set the name of the network interface



*Type:*
Network Interface Name ()

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.remote



The other tunnel endpoint’s IP address (unicast point-to-point
only, no multicast/BUM-flood mode in this module yet)\. Must be
a static, currently-correct, routable IP: NOT a hostname, and NOT
usable directly across NAT or a dynamic WAN IP on either end\.
This assumes both ends already sit on stable, mutually-routable
infrastructure\.



*Type:*
IP address



*Example:*

```nix
"172.20.1.1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.requiredForOnline



When configured to ` null ` (which is the default)\.

 - requiredForOnline will be set to ` true `
   if the interface is configured as ` dhcp.server `\.

 - requiredForOnline will be set to ` false `
   if the interface is configured as ` dhcp.client ` or ` dhcp.static `\.

This behavior can be overwritten by configuring this option to ` true ` and
the ` systemd-networkd-wait-online.service ` will
wait for this interface to be configured (until timeout)\.
Or set the option to ` false ` for the ` systemd-networkd-wait-online.service `
to ignore this interface\.



*Type:*
null or boolean



*Default:*

```nix
null
```



*Example:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.staticRoutes



Added static routes for the interface\.

In the case of ` dhcp.static `,
if the route should be configured as the default use ` 0.0.0.0/0 `\.



*Type:*
list of (Subnet)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "172.20.90.0/24"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.vni



VXLAN Network Identifier (VNI), 0-16777215\.



*Type:*
integer between 0 and 16777215 (both inclusive)



*Example:*

```nix
1000
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)


