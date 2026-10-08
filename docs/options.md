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
      client = { };
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



Configure this interface as a DHCP client\.



*Type:*
(submodule) or boolean convertible to it



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.client\.useRoutes



Accept classless static routes (DHCP option 121) advertised on
this interface\.

 - ` null ` (default): only on the interface named by
   ` defaultRouteInterface ` (same as before this option existed)\.
 - ` true `/` false `: always/never, regardless of
   ` defaultRouteInterface `\.

Independent of the DHCP-advertised gateway (option 3), which is
controlled separately and still only accepted on
` defaultRouteInterface `\.



*Type:*
null or boolean



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server



Configure this interface as a DHCP server (reservations, pools, PXE boot, etc\. – see the options below)\.



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



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.clientClasses



Define Kea client classes
(see https://kea\.readthedocs\.io/en/latest/arm/classify\.html)
scoped to this subnet\.

Each class is forced into evaluation for this subnet only
(Kea’s ` require-client-classes `), and its Kea class name is
this attribute’s name suffixed with this subnet’s ` id `
(e\.g\. ` my-class-204 `), guaranteeing global uniqueness
across interfaces – the same convention the built-in
PXE-boot classes already use\.

` test ` (Kea’s classification expression) is required;
every other field (` option-data `, ` next-server `,
` boot-file-name `, etc\.) is passed through to Kea verbatim
in Kea’s own JSON shape – see the docs above for the full
set of fields a class can carry\.



*Type:*
attribute set of (open submodule of attribute set of anything)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  dect-setup-1 = {
    option-data = [
      {
        data = "dect-setup-1.efi";
        name = "boot-file-name";
      }
    ];
    test = "substring(option[60].hex,0,8) == 'dect-dev'";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.clientClasses\.\<name>\.test



Kea classification test expression\.



*Type:*
string

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



Set the first IP address provided by the DHCP Server\.
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



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.disableTftpServerWarning



Suppress the build-time warning that ` tftpServer = false `
otherwise emits for this interface\. Use once you’ve set up
your own TFTP server and no longer need the reminder\.



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



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.defaultIso



Per-MAC override of ` pxe-boot.defaultIso `: which ISO
this specific reservation’s client should PXE boot
by default, instead of the interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultIso `\.



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



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.defaultScriptName



Per-MAC override of ` pxe-boot.defaultScriptName `:
which autoinstall script this specific reservation’s
client should use by default, instead of the
interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultScriptName `\.



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



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.tftpServer



Whether this router should run a TFTP server (` atftpd `,
bound to this interface’s own address), serving
` <tftpServer.root>/<id> ` (see ` tftpServerRoot ` below to
override the root for just this interface) for this
subnet\. Independent of ` pxe-boot.enable ` – it can run
standalone, with no PXE boot configured for this
interface at all (the directory is then created empty;
nothing stages files into it, so you populate it
yourself)\.

 - ` null ` (the default): on when ` pxe-boot.enable = true `,
   off otherwise\.
 - ` true `: always on, pxe-boot or not\.
 - ` false `: always off\.

Effect on ` pxe-boot `: this is what makes a PXE-boot-enabled
subnet’s grub/iPXE files (staged there regardless of this
option) actually reachable over the network\. Setting it
` false ` on such a subnet leaves those files staged but
unserved – you must run your own TFTP server against that
same directory, or PXE clients there can’t reach them\.
Triggers a build-time warning as a reminder (silence it
with ` pxe-boot.disableTftpServerWarning `)\.



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



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.server\.tftpServerRoot



Override ` my.router.tftpServer.root ` for just this
interface – it still gets its own ` <root>/<id> `
subdirectory underneath\. ` null ` (the default) inherits
the global root\.



*Type:*
null or absolute path



*Default:*

```nix
null
```



*Example:*

```nix
"/data/tftp-eth1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.bridgeInterfaces\.\<name>\.dhcp\.static



Assign a static IP to this interface, instead of running a DHCP client or server on it\.



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



IPv4 forwarding\. It is turned on by default\.



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



Enable multicast routing (pimd) and the IGMP querier on this
interface/bridge\.



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
Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters)

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
list of (Subnet in CIDR notation, network address only (e\.g\. 172\.20\.90\.0/24) – not a host IP address)



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



Create a bridge interface and include this interface in it\.



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
Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters)



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



Configure this interface as a DHCP client\.



*Type:*
(submodule) or boolean convertible to it



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.client\.useRoutes



Accept classless static routes (DHCP option 121) advertised on
this interface\.

 - ` null ` (default): only on the interface named by
   ` defaultRouteInterface ` (same as before this option existed)\.
 - ` true `/` false `: always/never, regardless of
   ` defaultRouteInterface `\.

Independent of the DHCP-advertised gateway (option 3), which is
controlled separately and still only accepted on
` defaultRouteInterface `\.



*Type:*
null or boolean



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server



Configure this interface as a DHCP server (reservations, pools, PXE boot, etc\. – see the options below)\.



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



## my\.router\.configInterface\.\<name>\.dhcp\.server\.clientClasses



Define Kea client classes
(see https://kea\.readthedocs\.io/en/latest/arm/classify\.html)
scoped to this subnet\.

Each class is forced into evaluation for this subnet only
(Kea’s ` require-client-classes `), and its Kea class name is
this attribute’s name suffixed with this subnet’s ` id `
(e\.g\. ` my-class-204 `), guaranteeing global uniqueness
across interfaces – the same convention the built-in
PXE-boot classes already use\.

` test ` (Kea’s classification expression) is required;
every other field (` option-data `, ` next-server `,
` boot-file-name `, etc\.) is passed through to Kea verbatim
in Kea’s own JSON shape – see the docs above for the full
set of fields a class can carry\.



*Type:*
attribute set of (open submodule of attribute set of anything)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  dect-setup-1 = {
    option-data = [
      {
        data = "dect-setup-1.efi";
        name = "boot-file-name";
      }
    ];
    test = "substring(option[60].hex,0,8) == 'dect-dev'";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.server\.clientClasses\.\<name>\.test



Kea classification test expression\.



*Type:*
string

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



Set the first IP address provided by the DHCP Server\.
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



## my\.router\.configInterface\.\<name>\.dhcp\.server\.pxe-boot\.disableTftpServerWarning



Suppress the build-time warning that ` tftpServer = false `
otherwise emits for this interface\. Use once you’ve set up
your own TFTP server and no longer need the reminder\.



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



## my\.router\.configInterface\.\<name>\.dhcp\.server\.reservations\.\<name>\.defaultIso



Per-MAC override of ` pxe-boot.defaultIso `: which ISO
this specific reservation’s client should PXE boot
by default, instead of the interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultIso `\.



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



## my\.router\.configInterface\.\<name>\.dhcp\.server\.reservations\.\<name>\.defaultScriptName



Per-MAC override of ` pxe-boot.defaultScriptName `:
which autoinstall script this specific reservation’s
client should use by default, instead of the
interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultScriptName `\.



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



## my\.router\.configInterface\.\<name>\.dhcp\.server\.tftpServer



Whether this router should run a TFTP server (` atftpd `,
bound to this interface’s own address), serving
` <tftpServer.root>/<id> ` (see ` tftpServerRoot ` below to
override the root for just this interface) for this
subnet\. Independent of ` pxe-boot.enable ` – it can run
standalone, with no PXE boot configured for this
interface at all (the directory is then created empty;
nothing stages files into it, so you populate it
yourself)\.

 - ` null ` (the default): on when ` pxe-boot.enable = true `,
   off otherwise\.
 - ` true `: always on, pxe-boot or not\.
 - ` false `: always off\.

Effect on ` pxe-boot `: this is what makes a PXE-boot-enabled
subnet’s grub/iPXE files (staged there regardless of this
option) actually reachable over the network\. Setting it
` false ` on such a subnet leaves those files staged but
unserved – you must run your own TFTP server against that
same directory, or PXE clients there can’t reach them\.
Triggers a build-time warning as a reminder (silence it
with ` pxe-boot.disableTftpServerWarning `)\.



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



## my\.router\.configInterface\.\<name>\.dhcp\.server\.tftpServerRoot



Override ` my.router.tftpServer.root ` for just this
interface – it still gets its own ` <root>/<id> `
subdirectory underneath\. ` null ` (the default) inherits
the global root\.



*Type:*
null or absolute path



*Default:*

```nix
null
```



*Example:*

```nix
"/data/tftp-eth1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.dhcp\.static



Assign a static IP to this interface, instead of running a DHCP client or server on it\.



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



IPv4 forwarding\. It is turned on by default\.



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



Enable multicast routing (pimd) and the IGMP querier on this
interface/bridge\.



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
Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters)

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
list of (Subnet in CIDR notation, network address only (e\.g\. 172\.20\.90\.0/24) – not a host IP address)



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



Create an interface to handle VLAN tagged packets received on this interface\.



*Type:*
list of (submodule)



*Default:*

```nix
[ ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.bridges



Create a bridge interface and include this interface in it\.



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
Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters)



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



Configure this interface as a DHCP client\.



*Type:*
(submodule) or boolean convertible to it



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.client\.useRoutes



Accept classless static routes (DHCP option 121) advertised on
this interface\.

 - ` null ` (default): only on the interface named by
   ` defaultRouteInterface ` (same as before this option existed)\.
 - ` true `/` false `: always/never, regardless of
   ` defaultRouteInterface `\.

Independent of the DHCP-advertised gateway (option 3), which is
controlled separately and still only accepted on
` defaultRouteInterface `\.



*Type:*
null or boolean



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server



Configure this interface as a DHCP server (reservations, pools, PXE boot, etc\. – see the options below)\.



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



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.clientClasses



Define Kea client classes
(see https://kea\.readthedocs\.io/en/latest/arm/classify\.html)
scoped to this subnet\.

Each class is forced into evaluation for this subnet only
(Kea’s ` require-client-classes `), and its Kea class name is
this attribute’s name suffixed with this subnet’s ` id `
(e\.g\. ` my-class-204 `), guaranteeing global uniqueness
across interfaces – the same convention the built-in
PXE-boot classes already use\.

` test ` (Kea’s classification expression) is required;
every other field (` option-data `, ` next-server `,
` boot-file-name `, etc\.) is passed through to Kea verbatim
in Kea’s own JSON shape – see the docs above for the full
set of fields a class can carry\.



*Type:*
attribute set of (open submodule of attribute set of anything)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  dect-setup-1 = {
    option-data = [
      {
        data = "dect-setup-1.efi";
        name = "boot-file-name";
      }
    ];
    test = "substring(option[60].hex,0,8) == 'dect-dev'";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.clientClasses\.\<name>\.test



Kea classification test expression\.



*Type:*
string

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



Set the first IP address provided by the DHCP Server\.
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



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.pxe-boot\.disableTftpServerWarning



Suppress the build-time warning that ` tftpServer = false `
otherwise emits for this interface\. Use once you’ve set up
your own TFTP server and no longer need the reminder\.



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



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.reservations\.\<name>\.defaultIso



Per-MAC override of ` pxe-boot.defaultIso `: which ISO
this specific reservation’s client should PXE boot
by default, instead of the interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultIso `\.



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



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.reservations\.\<name>\.defaultScriptName



Per-MAC override of ` pxe-boot.defaultScriptName `:
which autoinstall script this specific reservation’s
client should use by default, instead of the
interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultScriptName `\.



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



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.tftpServer



Whether this router should run a TFTP server (` atftpd `,
bound to this interface’s own address), serving
` <tftpServer.root>/<id> ` (see ` tftpServerRoot ` below to
override the root for just this interface) for this
subnet\. Independent of ` pxe-boot.enable ` – it can run
standalone, with no PXE boot configured for this
interface at all (the directory is then created empty;
nothing stages files into it, so you populate it
yourself)\.

 - ` null ` (the default): on when ` pxe-boot.enable = true `,
   off otherwise\.
 - ` true `: always on, pxe-boot or not\.
 - ` false `: always off\.

Effect on ` pxe-boot `: this is what makes a PXE-boot-enabled
subnet’s grub/iPXE files (staged there regardless of this
option) actually reachable over the network\. Setting it
` false ` on such a subnet leaves those files staged but
unserved – you must run your own TFTP server against that
same directory, or PXE clients there can’t reach them\.
Triggers a build-time warning as a reminder (silence it
with ` pxe-boot.disableTftpServerWarning `)\.



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



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.server\.tftpServerRoot



Override ` my.router.tftpServer.root ` for just this
interface – it still gets its own ` <root>/<id> `
subdirectory underneath\. ` null ` (the default) inherits
the global root\.



*Type:*
null or absolute path



*Default:*

```nix
null
```



*Example:*

```nix
"/data/tftp-eth1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\<name>\.vlans\.\*\.dhcp\.static



Assign a static IP to this interface, instead of running a DHCP client or server on it\.



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



IPv4 forwarding\. It is turned on by default\.



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



Enable multicast routing (pimd) and the IGMP querier on this
interface/bridge\.



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
null or (Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters))



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
list of (Subnet in CIDR notation, network address only (e\.g\. 172\.20\.90\.0/24) – not a host IP address)



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



Name of the network interface with the default route\.

When using this module’s generated nftables ruleset (i\.e\. no
` ./netfilter.ruleset ` override file present), this interface
also gets IP masquerade (NAT) enabled automatically, regardless
of its own ` ipMasquerade ` setting\.



*Type:*
Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters)



*Default:*

```nix
"builtin-ether"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.defaultRouteMetric



Set the metric (priority) for the default route,
in case another service also tries to configure a default route\.



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



DHCP lease timers and the domain name handed out to clients\.



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
fires – no error is logged, the only symptom is the hook
point silently not firing\. So every entry here shares a
single generated dispatcher script and a single real Kea ` hooks-libraries `
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
prepare supported Linux distributions for download\.



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



Provide the content of the script or the path to the script\.

SECURITY: a literal string value here is written to
the world-readable Nix store (/nix/store) and served
completely unauthenticated over plain HTTP on the
LAN (anyone who can reach this router’s network can
download it)\. Do not put secrets – passwords, API
keys, private keys – directly in this value\. Use a
path to a file managed by a proper secrets mechanism
(e\.g\. sops-nix) if the script needs to reference a
secret, and have the installer itself fetch/decrypt
it at install time instead\.



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



## my\.router\.pxe-boot\.isoDownloadRateLimit



Caps the transfer rate of whole-ISO downloads served under
` /isos/ ` (nginx’s ` limit_rate `, e\.g\. a client’s own
` findiso= ` fetch)\. ` null ` (the default) means unlimited\.

A bulk ISO transfer and other clients’ latency-sensitive GRUB
kernel/initrd fetches share the same nginx worker process;
on a very weak/single-core router this can starve those
latency-sensitive requests enough to make GRUB’s legacy
BIOS/SeaBIOS PXE network driver (which has no retry logic)
fail entirely\. Real routers typically have enough cores that
this never actually contends – this project’s own E2E test
runs its router VM with a single vCPU and sets this
explicitly, which real deployments normally won’t need to\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"20m"
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



## my\.router\.pxe-boot\.nixIsos



ISO images built by Nix (e\.g\. this project’s own
` modules/iso-builder `) to serve for PXE boot, without needing
to manually copy them into ` isoFolderPath `\. Each package is
exposed via a ` systemd.tmpfiles.rules "L+" ` symlink farm –
atomic and generation-pinned: removing a package from this
list changes what the farm contains on the next switch, so no
manually-managed symlinks can be orphaned\.

Inert unless ` pxe-boot.enable ` is also set – the farm and
its ` tmpfiles.rules ` entry only exist inside that same
` lib.mkIf `\.

` autoinstall ` and each interface’s ` defaultIso ` key by ISO
*filename* (the package’s ` image.fileName `/` p.name `), the
same as for ` isoFolderPath `-discovered ISOs – there is
nothing ` nixIsos `-specific to configure on that side, just
use the same filename there too\.



*Type:*
list of package



*Default:*

```nix
[ ]
```



*Example:*

```nix
[ self.packages.x86_64-linux.iso-x86_64 ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.nixIsosDir



Where the ` nixIsos ` symlink farm is exposed via
` systemd.tmpfiles.rules "L+" ` (added to ` isoFolderPaths `
alongside the manually-managed ` isoFolderPath ` whenever
` nixIsos ` is non-empty)\.



*Type:*
absolute path



*Default:*

```nix
"/var/lib/pxe-boot/nix-isos"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.shimPackage



The signed shim + GRUB build served over TFTP as
` bootx64.efi `/` bootaa64.efi ` for UEFI Secure Boot clients
(see ` tests/pxe-boot/secure-boot.nix `)\. Overridable so an
operator can supply their own MOK-enrolled shim, pin a
different Ubuntu netboot release than this module’s own
auto-bumped default, or substitute a signed build obtained
through a different trust chain entirely – without forking
this module\.

Defaults to this project’s own ` pxe-boot-grub-signed `
package (` packages/pxe-boot-grub-signed/package.nix `),
Canonical/Microsoft-signed shim + GRUB repackaged from
Ubuntu’s netboot tarball\.



*Type:*
package



*Default:*

```nix
pkgs.callPackage ../packages/pxe-boot-grub-signed/package.nix { }
```



*Example:*

```nix
pkgs.my-custom-signed-grub
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.tftpServer\.root



Base directory TFTP-serving interfaces stage files under and
atftpd serves from – each interface gets its own
` <root>/<id> ` subdirectory\. pxe-boot follows this same root
for the grub/iPXE files it stages; it does not have its own
separate path setting\.

Override per-interface with
` dhcp.server.tftpServerRoot `\.



*Type:*
absolute path



*Default:*

```nix
"/srv/pxeboot"
```



*Example:*

```nix
"/data/tftp"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces



Config all VXLAN interfaces (unicast with ` remote `, multicast with ` group ` and ` device `, or hub with ` listen `)



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
  vxlan3000 = {
    device = "eth1";
    dhcp = {
      client = { };
    };
    group = "239.1.1.1";
    vni = 3000;
  };
  vxlan4000 = {
    dhcp = {
      server = {
        address = "10.102.0.1/24";
      };
    };
    listen = true;
    vni = 4000;
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.bridges



Create a bridge interface and include this interface in it\.



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
Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters)



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



## my\.router\.vxlanInterfaces\.\<name>\.device



Multicast mode: name of the underlay interface (a
` configInterface ` or ` bridgeInterfaces ` entry) that joins ` group `\.
Required with ` group `; must be ` null ` otherwise\.



*Type:*
null or (Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters))



*Default:*

```nix
null
```



*Example:*

```nix
"eth1"
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



Configure this interface as a DHCP client\.



*Type:*
(submodule) or boolean convertible to it



*Default:*

```nix
{ }
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.client\.useRoutes



Accept classless static routes (DHCP option 121) advertised on
this interface\.

 - ` null ` (default): only on the interface named by
   ` defaultRouteInterface ` (same as before this option existed)\.
 - ` true `/` false `: always/never, regardless of
   ` defaultRouteInterface `\.

Independent of the DHCP-advertised gateway (option 3), which is
controlled separately and still only accepted on
` defaultRouteInterface `\.



*Type:*
null or boolean



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server



Configure this interface as a DHCP server (reservations, pools, PXE boot, etc\. – see the options below)\.



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



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.clientClasses



Define Kea client classes
(see https://kea\.readthedocs\.io/en/latest/arm/classify\.html)
scoped to this subnet\.

Each class is forced into evaluation for this subnet only
(Kea’s ` require-client-classes `), and its Kea class name is
this attribute’s name suffixed with this subnet’s ` id `
(e\.g\. ` my-class-204 `), guaranteeing global uniqueness
across interfaces – the same convention the built-in
PXE-boot classes already use\.

` test ` (Kea’s classification expression) is required;
every other field (` option-data `, ` next-server `,
` boot-file-name `, etc\.) is passed through to Kea verbatim
in Kea’s own JSON shape – see the docs above for the full
set of fields a class can carry\.



*Type:*
attribute set of (open submodule of attribute set of anything)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  dect-setup-1 = {
    option-data = [
      {
        data = "dect-setup-1.efi";
        name = "boot-file-name";
      }
    ];
    test = "substring(option[60].hex,0,8) == 'dect-dev'";
  };
}
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.clientClasses\.\<name>\.test



Kea classification test expression\.



*Type:*
string

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



Set the first IP address provided by the DHCP Server\.
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



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.pxe-boot\.disableTftpServerWarning



Suppress the build-time warning that ` tftpServer = false `
otherwise emits for this interface\. Use once you’ve set up
your own TFTP server and no longer need the reminder\.



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



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.defaultIso



Per-MAC override of ` pxe-boot.defaultIso `: which ISO
this specific reservation’s client should PXE boot
by default, instead of the interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultIso `\.



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



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.reservations\.\<name>\.defaultScriptName



Per-MAC override of ` pxe-boot.defaultScriptName `:
which autoinstall script this specific reservation’s
client should use by default, instead of the
interface-wide default\.

Only takes effect when ` pxe-boot.enable ` is also
true for this interface\. Leave unset (empty string)
to inherit the interface-wide ` defaultScriptName `\.



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



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.tftpServer



Whether this router should run a TFTP server (` atftpd `,
bound to this interface’s own address), serving
` <tftpServer.root>/<id> ` (see ` tftpServerRoot ` below to
override the root for just this interface) for this
subnet\. Independent of ` pxe-boot.enable ` – it can run
standalone, with no PXE boot configured for this
interface at all (the directory is then created empty;
nothing stages files into it, so you populate it
yourself)\.

 - ` null ` (the default): on when ` pxe-boot.enable = true `,
   off otherwise\.
 - ` true `: always on, pxe-boot or not\.
 - ` false `: always off\.

Effect on ` pxe-boot `: this is what makes a PXE-boot-enabled
subnet’s grub/iPXE files (staged there regardless of this
option) actually reachable over the network\. Setting it
` false ` on such a subnet leaves those files staged but
unserved – you must run your own TFTP server against that
same directory, or PXE clients there can’t reach them\.
Triggers a build-time warning as a reminder (silence it
with ` pxe-boot.disableTftpServerWarning `)\.



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



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.server\.tftpServerRoot



Override ` my.router.tftpServer.root ` for just this
interface – it still gets its own ` <root>/<id> `
subdirectory underneath\. ` null ` (the default) inherits
the global root\.



*Type:*
null or absolute path



*Default:*

```nix
null
```



*Example:*

```nix
"/data/tftp-eth1"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.dhcp\.static



Assign a static IP to this interface, instead of running a DHCP client or server on it\.



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



IPv4 forwarding\. It is turned on by default\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.group

Multicast mode: the multicast group every peer joins
(224\.0\.0\.0 - 239\.255\.255\.255)\. All peers of one VXLAN must use
the same group\. Set exactly one of ` remote `, ` group ` or ` listen `\.
Needs ` device `\.

See ` docs/vxlan-modes-and-dhcp.md ` for how to set this up by hand\.



*Type:*
null or (Multicast Address (224\.0\.0\.0 - 239\.255\.255\.255))



*Default:*

```nix
null
```



*Example:*

```nix
"239.1.1.1"
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



## my\.router\.vxlanInterfaces\.\<name>\.listen



Listen mode: act as a hub that clients connect to\. The interface
has no fixed peer; it learns each client’s address from the
frames the client sends, and replies to it\. Clients are normal
unicast VXLANs with ` remote ` set to this host\. Set exactly one
of ` remote `, ` group ` or ` listen `\.

The hub cannot start talking to a client it has not heard from
yet, and forgets idle clients after a few minutes\. See
` docs/vxlan-modes-and-dhcp.md ` (also covers clients behind NAT)\.



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
pick the address the routing table would use to reach ` remote `
(in multicast mode, an address on ` device `; in ` listen ` mode,
all addresses)\.



*Type:*
null or (IP address)



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.multicast



Enable multicast routing (pimd) and the IGMP querier on this
interface/bridge\.



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
Network Interface Name (letters, digits, \`\.\`, \`_\`, \`-\`; max 15 characters)

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.vxlanInterfaces\.\<name>\.remote



Unicast mode: the other tunnel endpoint’s IP address\. Set exactly
one of ` remote `, ` group ` or ` listen `\.

Must be a static, routable IP (not a hostname, and not usable
across NAT or a dynamic WAN IP)\.



*Type:*
null or (IP address)



*Default:*

```nix
null
```



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
list of (Subnet in CIDR notation, network address only (e\.g\. 172\.20\.90\.0/24) – not a host IP address)



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



## pxe-boot-iso (modules/iso-builder)

## pxe-boot-iso\.enable

Whether to enable PXE-bootable ISO configuration\.



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
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.enableNetworkDownload



Enable downloading ISO via network during initrd\.
This allows using findiso=http://… kernel parameter to download the ISO over network\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.extraPackages



Additional packages to include in the ISO



*Type:*
list of package



*Default:*

```nix
[ ]
```



*Example:*

```nix
[ pkgs.vim pkgs.git ]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.includeDiskTools



Include disk utilities (parted, gparted, etc\.)



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.includeHardwareTools



Include hardware testing tools (lshw, hwinfo, etc\.)



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.includeNetworkTools



Include network troubleshooting tools (tcpdump, nmap, etc\.)



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.kernelPackage



Kernel packages to use (linuxPackages_\* attrset)



*Type:*
raw value



*Default:*

```nix
pkgs.linuxPackages_latest
```



*Example:*

```nix
pkgs.linuxPackages_6_12
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.networkDownloadStallTimeoutSec



Abort the network ISO download if no data has been received for
this many seconds (passed to wget as ` --read-timeout `)\. This is a
STALL timeout, not a total-duration cap: it resets on every byte
received, so a large ISO on a slow-but-working link can take as
long as it needs – only genuine inactivity triggers it\.

Design note: the systemd stage-1 ` findiso-download.service ` unit
itself has no total-duration timeout either (no
` JobRunningTimeoutSec= `) – this STALL timeout is the only
safety net against an unbounded hang\. On expiry, wget exits
non-zero after exhausting its own bounded retry budget
(` --tries `, default 20), which the service’s
` OnFailure=emergency.target ` catches, rather than leaving the
boot waiting forever for a download that will never finish\.



*Type:*
signed integer



*Default:*

```nix
60
```



*Example:*

```nix
120
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.networkDownloadTmpfsSize



Size of the tmpfs used to stage the network-downloaded ISO during
initrd (passed as ` mount -t tmpfs -o size=... `)\. Must be large
enough to hold the whole ISO in RAM\.



*Type:*
string



*Default:*

```nix
"2G"
```



*Example:*

```nix
"4G"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.ssh\.enable



Whether to enable SSH server



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.ssh\.passwordAuthentication



Whether to allow SSH password authentication\.

 - null: Automatically set to false if sshAuthorizedKeys is provided, true otherwise - DEFAULT
 - true: Allow password authentication
 - false: Disable password authentication (keys only)



*Type:*
null or boolean



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.ssh\.permitRootLogin



Whether to allow root login via SSH



*Type:*
one of “yes”, “no”, “prohibit-password”, “forced-commands-only”



*Default:*

```nix
"yes"
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.sshAuthorizedKeys



SSH authorized keys for the nixos user



*Type:*
list of string



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "ssh-ed25519 AAAAC3Nz... user@host"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.users\.nixos\.allowSudoWithoutPassword



Allow nixos user to use sudo without password



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.users\.nixos\.hashedPassword



Hashed password for the nixos user (e\.g\., from mkpasswd)\.
Cannot be used together with password\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.users\.nixos\.password



Plain text password for the nixos user\.

 - null: Empty password (login without password) - DEFAULT
 - “somepassword”: Sets this password
   Cannot be used together with hashedPassword\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.users\.root\.hashedPassword



Hashed password for the root user (e\.g\., from mkpasswd)\.
Cannot be used together with password\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)



## pxe-boot-iso\.users\.root\.password



Plain text password for the root user\.

 - null: Empty password (login without password) - DEFAULT
 - “somepassword”: Sets this password
   Cannot be used together with hashedPassword\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder](file:///home/runner/work/nixos-router-module/nixos-router-module/modules/iso-builder)


