# VXLAN multicast mode

A VXLAN interface can connect to its peers in one of two ways:

```
UNICAST  (remote = "<peer ip>")        MULTICAST  (group = "239.1.1.1")

 r1 ----------> r2                      r1       r2       r3
 one `remote` per peer                   |        |        |
                                        eth1     eth1     eth1   <- each joins the group
                                         |        |        |
                                      ===+========+========+===  underlay network
                                      unknown/broadcast traffic goes to the group;
                                      every peer receives it, no peer list needed
```

Use unicast for a fixed pair of routers. Use multicast when several routers share one
VXLAN and the underlay network carries multicast.

## With this module

```nix
my.router.vxlanInterfaces.vxlan3000 = {
  vni = 3000;
  group = "239.1.1.1";   # multicast group, 224.0.0.0 - 239.255.255.255
  device = "eth1";       # underlay interface that joins the group
};
```

- Set `group` **or** `remote`, never both.
- `group` and `device` are set together. `device` must be a `configInterface` or
  `bridgeInterfaces` entry.
- All peers of one VXLAN use the same `vni` and `group`.

To get an address from a DHCP server on the VXLAN segment, add the DHCP client:

```nix
my.router.vxlanInterfaces.vxlan3000.dhcp.client = { };
```

Add `useRoutes = true;` inside the braces to also accept classless static routes
(see the `dhcp.client` option).

## By hand (without this module)

Create the interface and bring it up. It is gone after a reboot.

```
ip link add vxlan3000 type vxlan id 3000 group 239.1.1.1 dev eth1 dstport 4789
ip link set vxlan3000 up
```

Check it:

```
ip -d link show vxlan3000   # ... vxlan id 3000 group 239.1.1.1 dev eth1 ... dstport 4789
ip maddr show dev eth1      # ... inet  239.1.1.1
```

Run the DHCP client on it with systemd-networkd. Save this as
`/etc/systemd/network/40-vxlan3000.network`:

```
[Match]
Name=vxlan3000

[Network]
DHCP=ipv4
LinkLocalAddressing=no
```

Then `networkctl reload`. A DHCP server must be reachable on the VXLAN segment.

## Routed underlay

On one shared network segment, the group join above is all that is needed. If the
underlay has routers between the peers, those hops must route the multicast group:
set `multicast = true;` on the underlay interface so `pimd` runs on it. This module
does not enable that for you.

## Troubleshooting

- `vxlan3000` is never created: no underlay `.network` file lists it with
  `VXLAN=vxlan3000`. The module adds that line to `<device>`'s `.network` file
  (see `networkctl cat <device>`).
- No traffic between peers: check `ip maddr show dev <device>` on both sides, and that
  the underlay passes multicast (switch IGMP snooping needs a querier).
