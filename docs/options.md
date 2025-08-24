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

*Declared by:*
 - [\<nixpkgs/lib/modules\.nix>](https://github.com/NixOS/nixpkgs/blob//lib/modules.nix)



## my\.router\.enable



Enable Router module



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface



List of configured network interfaces



*Type:*
list of (submodule)



*Default:*
` [ ] `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.bridges



Creating a bridge interface with and include this interface in the bridge\.



*Type:*
list of (submodule)



*Default:*
` [ ] `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.bridges\.\*\.name



Select the name of the bridge interface



*Type:*
null or (Network Interface Name ())



*Example:*
` "br0" `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.dhcp



Select if this network interface should be configured for DHCP Server or Client\.
It is also possible to just assign a static IP\.



*Type:*
null or attribute-tagged union



*Default:*
` null `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.dhcp\.client



To-do: make description



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.dhcp\.server



To-do: make description



*Type:*
submodule



*Default:*
` { } `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.dhcp\.server\.classless-static-route



Expose all other subnets, declared as a ` dhcp.server.gateway `,
as a classless static route (Option: 121)\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## my\.router\.configInterface\.\*\.dhcp\.server\.default-route



Provide DHCP clients with a default route



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## my\.router\.configInterface\.\*\.dhcp\.server\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*
` [ ] `



## my\.router\.configInterface\.\*\.dhcp\.server\.firstIP



Set the first IP address provides by the DHCP Server\.
Example: ` 10 ` for subnet ` 192.168.1.0/24 `
will be calculated to ` 192.168.1.10 `\.



*Type:*
signed integer



*Default:*
` 5 `



## my\.router\.configInterface\.\*\.dhcp\.server\.gateway



Set the gateway for the subnet



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Default:*
` "" `



## my\.router\.configInterface\.\*\.dhcp\.server\.id



Subnet IDs must be greater than zero and less than 4294967295



*Type:*
integer between 1 and 4294967294 (both inclusive)



*Default:*
` 1024 `



## my\.router\.configInterface\.\*\.dhcp\.server\.pxe-boot\.enable



Enable PXE Boot support for this network interface\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## my\.router\.configInterface\.\*\.dhcp\.server\.pxe-boot\.defaultIso



Select which ISO file should be selected by default\.



*Type:*
string



*Default:*
` "" `



*Example:*
` "rhel-9.6-x86_64-dvd.iso" `



## my\.router\.configInterface\.\*\.dhcp\.server\.pxe-boot\.defaultScriptName



Select which autoinstall script should be selected by default\.



*Type:*
string



*Default:*
` "" `



*Example:*
` "minimal-environment.kstart" `



## my\.router\.configInterface\.\*\.dhcp\.server\.reservations



Make reservations (MAC address specific configurations)\.
Example: Make it so that one IP address is always provided to
the selected MAC address\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  "00:11:22:33:44:55" = {
    ip-address = "192.168.1.2";
  };
}
```



## my\.router\.configInterface\.\*\.dhcp\.server\.reservations\.\<name>\.ip-address



Bind the IP address the MAC address (attribute key)



*Type:*
null or (IP address)



*Default:*
` null `



## my\.router\.configInterface\.\*\.dhcp\.server\.reservations-only



Only reply to the client which matches the information in ` dhcp.server.reservations `\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## my\.router\.configInterface\.\*\.dhcp\.static



To-do: make description (Note static IP is put here, but there may be a better location in the structure)



*Type:*
submodule



*Default:*
` { } `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.dhcp\.static\.dns-servers



Set the IP address(es) of the dns-server(s)



*Type:*
list of (IP address)



*Default:*
` [ ] `



*Example:*

```
[
  "192.168.1.1"
  "1.1.1.1"
]
```



## my\.router\.configInterface\.\*\.dhcp\.static\.gateway



Set the IP address of the gateway



*Type:*
null or (IP address)



*Default:*
` null `



*Example:*
` "192.168.1.1" `



## my\.router\.configInterface\.\*\.dhcp\.static\.ip-address



```
            Set the ip and subnet in the CIDR format.
```



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*
` "192.168.1.10/24" `



## my\.router\.configInterface\.\*\.excludeFromNetworkManager



Ensure that the interface is excluded from NetworkManager



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.forwarding



IPv4 forwarding\. It is turn on by default\.



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.ipMasquerade



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.linkConfig



Alias for ` systemd.network.links.<name>.linkConfig `\.

Basically live copy-paste of the NixOS ` options ` for this systemd setting\.



*Type:*
attribute set

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.mac



MAC address of the network interface\.

It can be either a MAC-address or list of MAC-addresses\.

**Example:** A list of MAC-addresses can make sense if you have multiple
USB adapter which are not connected at the same time, but you want to have
the same network interface name (and want to be configured the same)



*Type:*
null or (list of (Mac Address (use \`:\` or \`-\` as separator))) or (Mac Address (use \`:\` or \`-\` as separator))

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.multicast



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.name



Set the name of the network interface



*Type:*
Network Interface Name ()

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.requiredForOnline



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
` null `



*Example:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.staticRoutes



Added static routes for the interface\.

In the case of ` dhcp.static `,
if the route should be configured as the default use ` 0.0.0.0/0 `\.



*Type:*
list of (Subnet)



*Default:*
` [ ] `



*Example:*

```
[
  "172.20.90.0/24"
]
```

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans



Create a interface to handle VLAN tagged packages recieved on this interface\.



*Type:*
list of (submodule)



*Default:*
` [ ] `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp



Select if this network interface should be configured for DHCP Server or Client\.
It is also possible to just assign a static IP\.



*Type:*
null or attribute-tagged union



*Default:*
` null `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.client



To-do: make description



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server



To-do: make description



*Type:*
submodule



*Default:*
` { } `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.classless-static-route



Expose all other subnets, declared as a ` dhcp.server.gateway `,
as a classless static route (Option: 121)\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.default-route



Provide DHCP clients with a default route



*Type:*
boolean



*Default:*
` true `



*Example:*
` false `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*
` [ ] `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.firstIP



Set the first IP address provides by the DHCP Server\.
Example: ` 10 ` for subnet ` 192.168.1.0/24 `
will be calculated to ` 192.168.1.10 `\.



*Type:*
signed integer



*Default:*
` 5 `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.gateway



Set the gateway for the subnet



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Default:*
` "" `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.id



Subnet IDs must be greater than zero and less than 4294967295



*Type:*
integer between 1 and 4294967294 (both inclusive)



*Default:*
` 1024 `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.pxe-boot\.enable



Enable PXE Boot support for this network interface\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.pxe-boot\.defaultIso



Select which ISO file should be selected by default\.



*Type:*
string



*Default:*
` "" `



*Example:*
` "rhel-9.6-x86_64-dvd.iso" `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.pxe-boot\.defaultScriptName



Select which autoinstall script should be selected by default\.



*Type:*
string



*Default:*
` "" `



*Example:*
` "minimal-environment.kstart" `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.reservations



Make reservations (MAC address specific configurations)\.
Example: Make it so that one IP address is always provided to
the selected MAC address\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



*Example:*

```
{
  "00:11:22:33:44:55" = {
    ip-address = "192.168.1.2";
  };
}
```



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.reservations\.\<name>\.ip-address



Bind the IP address the MAC address (attribute key)



*Type:*
null or (IP address)



*Default:*
` null `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.server\.reservations-only



Only reply to the client which matches the information in ` dhcp.server.reservations `\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.static



To-do: make description (Note static IP is put here, but there may be a better location in the structure)



*Type:*
submodule



*Default:*
` { } `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.static\.dns-servers



Set the IP address(es) of the dns-server(s)



*Type:*
list of (IP address)



*Default:*
` [ ] `



*Example:*

```
[
  "192.168.1.1"
  "1.1.1.1"
]
```



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.static\.gateway



Set the IP address of the gateway



*Type:*
null or (IP address)



*Default:*
` null `



*Example:*
` "192.168.1.1" `



## my\.router\.configInterface\.\*\.vlans\.\*\.dhcp\.static\.ip-address



```
            Set the ip and subnet in the CIDR format.
```



*Type:*
CIDR (IP and Subnet\. Example: 192\.168\.1\.4/24)



*Example:*
` "192.168.1.10/24" `



## my\.router\.configInterface\.\*\.vlans\.\*\.excludeFromNetworkManager



Ensure that the interface is excluded from NetworkManager



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.forwarding



IPv4 forwarding\. It is turn on by default\.



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.id



Set VLan ID of the network interface



*Type:*
integer between 1 and 4096 (both inclusive)



*Default:*
` 0 `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.ipMasquerade



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.multicast



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.name



Option for setting the name of the VLAN
Otherwise it will get the default name: vlan-\<ID>



*Type:*
null or (Network Interface Name ())



*Default:*
` null `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.requiredForOnline



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
` null `



*Example:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.configInterface\.\*\.vlans\.\*\.staticRoutes



Added static routes for the interface\.

In the case of ` dhcp.static `,
if the route should be configured as the default use ` 0.0.0.0/0 `\.



*Type:*
list of (Subnet)



*Default:*
` [ ] `



*Example:*

```
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
` "builtin-ether" `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings



Config



*Type:*
submodule



*Default:*
` { } `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.domainName



Provide list of Domain Name(s)



*Type:*
list of (FQDN (Fully Qualified Domain Name))



*Default:*
` [ ] `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.rebindTimer



Set rebind time (seconds)



*Type:*
signed integer



*Default:*
` 2000 `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.renewTimer



Set renew time (seconds)



*Type:*
signed integer



*Default:*
` 1000 `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.generalSettings\.validLifetime



Set valid lifetime (seconds)



*Type:*
signed integer



*Default:*
` 4000 `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase



Specify the type of lease database



*Type:*
submodule



*Default:*
` { } `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase\.name



Set location for database lease file



*Type:*
absolute path



*Default:*
` /var/lib/kea/dhcp4.leases `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase\.persist



Should the leases stored in the lease-file be persistent



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.dhcp\.server\.leaseDatabase\.type



Only the ` memfile ` option is available



*Type:*
value “memfile” (singular enum)



*Default:*
` "memfile" `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.enable



Enable support for PXE Boot\.

This will download PXE boot binaries and
prepare supported Linux distrobutions for download\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.autoinstall



Configure autoinstall script for the different ISOs



*Type:*
attribute set of list of (submodule)



*Default:*
` { } `



*Example:*

```
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
` /home/runner/work/nixos-router-module/nixos-router-module/nixosModule/path/to/script.kstart `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.autoinstall\.\<name>\.\*\.scriptName



Name of the script in the GRUB Menu\.



*Type:*
string



*Example:*
` "minimal-environment.kstart" `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)



## my\.router\.pxe-boot\.isoFolderPath



Path to the folder which contains the iso files\.



*Type:*
absolute path



*Example:*
` "/data/iso" `

*Declared by:*
 - [/home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options\.nix](file:///home/runner/work/nixos-router-module/nixos-router-module/nixosModule/options.nix)


