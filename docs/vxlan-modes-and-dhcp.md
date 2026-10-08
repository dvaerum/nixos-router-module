# VXLAN: modes, and getting an address with DHCP

A VXLAN interface connects to its peers in one of three ways. Set exactly one of
`remote`, `group` or `listen` on each `vxlanInterfaces` entry.

```
UNICAST (remote)        MULTICAST (group + device)         LISTEN (hub)

 r1 ------> r2           r1       r2       r3               client A --\
 one remote              |        |        |                            >-- hub
 per peer               eth1     eth1     eth1  <- join    client B --/   (learns A and B
                         |        |        |       group                   from their frames)
                      ===+========+========+===  underlay
```

| Mode | Use it when | Peers |
|------|-------------|-------|
| unicast | a fixed pair of routers | `remote` = the other end |
| multicast | several routers share one VXLAN on a network that carries multicast | `group` + `device` |
| listen | one hub, clients connect to it, no list of clients | hub: `listen`; clients: `remote` = hub |

All peers of one VXLAN use the same `vni`. The module turns the firewall off, so UDP
4789 needs no rule on a host that uses it. Hosts that run their own firewall must allow
UDP 4789.

Use one tool (module, `ip`, `dhcpcd` or `nmcli`) per interface.

## Unicast

```nix
my.router.vxlanInterfaces.vxlan1000 = {
  vni = 1000;
  remote = "172.20.1.1";    # static, routable IP of the other end
  dhcp.static.ip-address = "10.100.0.2/30";
};
```

By hand: `ip link add vxlan1000 type vxlan id 1000 remote 172.20.1.1 dstport 4789`,
then `ip link set vxlan1000 up`.

## Multicast

```nix
my.router.vxlanInterfaces.vxlan3000 = {
  vni = 3000;
  group = "239.1.1.1";   # 224.0.0.0 - 239.255.255.255
  device = "eth1";       # underlay interface that joins the group
};
```

`group` and `device` are set together. `device` must be a `configInterface` or
`bridgeInterfaces` entry.

By hand, on every peer (gone after a reboot):

```
ip link add vxlan3000 type vxlan id 3000 group 239.1.1.1 dev eth1 dstport 4789
ip link set vxlan3000 up
```

With NetworkManager instead, this survives a reboot (`vxlan.remote` is the group,
`vxlan.parent` is the underlay interface):

```
nmcli connection add type vxlan con-name vxlan3000 ifname vxlan3000 \
  vxlan.id 3000 vxlan.remote 239.1.1.1 vxlan.parent eth1 vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses 10.101.0.2/24 ipv6.method disabled
```

Check it:

```
ip -d link show vxlan3000   # ... vxlan id 3000 group 239.1.1.1 dev eth1 ... dstport 4789
ip maddr show dev eth1      # ... inet  239.1.1.1
```

Routed underlay: on one shared network segment the group join is all that is needed. If
there are routers between the peers, they must route the group: set `multicast = true;`
on the underlay interface so `pimd` runs on it. This module does not do that for you.

## Listen (hub)

The hub has no list of clients. It learns each client's address from the frames the
client sends, and replies to it.

Hub:

```nix
my.router.vxlanInterfaces.vxlan4000 = {
  vni = 4000;
  listen = true;
  local = "203.0.113.10";                 # optional: address to bind (default: all)
  dhcp.server.address = "10.102.0.1/24";  # optional: hand out addresses to clients
};
```

Client:

```nix
my.router.vxlanInterfaces.vxlan4000 = {
  vni = 4000;
  remote = "203.0.113.10";   # the hub
  dhcp.client = { };
};
```

By hand, hub (no `remote`, which is what makes it a hub):

```
ip link add vxlan4000 type vxlan id 4000 local 203.0.113.10 dstport 4789
ip link set vxlan4000 up
ip addr add 10.102.0.1/24 dev vxlan4000
```

With NetworkManager instead:

```
nmcli connection add type vxlan con-name vxlan4000 ifname vxlan4000 \
  vxlan.id 4000 vxlan.local 203.0.113.10 vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses 10.102.0.1/24 ipv6.method disabled
```

Check it (a client shows up on the hub only after it has sent something):

```
ip -d link show vxlan4000      # "vxlan id 4000 local ..." with no remote or group
bridge fdb show dev vxlan4000  # "<client mac> dst <client ip>"
```

Limits:
- The hub cannot start talking to a client it has not heard from. The client must send
  first (its DHCP request, or a ping).
- Idle clients are forgotten after 300 seconds; the client must send again.
- The tunnel is not encrypted.

### Client behind NAT: keep the tunnel alive

VXLAN sends nothing when idle, so a NAT forgets the mapping after its UDP timeout
(often 30 to 120 seconds). Keep a ping to the hub running through the tunnel, more often
than that:

```
ping -i 20 -q 10.102.0.1 >/dev/null &
```

Or as a systemd unit that restarts itself (it lasts until reboot):

```
systemd-run --unit=vxlan-keepalive --property=Restart=always ping -i 20 -q 10.102.0.1
systemctl stop vxlan-keepalive      # to stop it
```

This is only a workaround. The hub replies to the standard VXLAN port, not the port the
NAT mapped for the client, so some NATs still break it. For clients behind NAT, run
VXLAN over WireGuard instead: point `remote` at the hub's WireGuard address.

## DHCP on a VXLAN (any mode)

One peer is the DHCP server, the others are clients. With this module that is
`dhcp.server.address = "...";` on the server and `dhcp.client = { };` on the clients
(add `useRoutes = true;` to also accept classless static routes; see the `dhcp.client`
option). By hand, with commands only:

Server. The VXLAN needs an address first. `--port=0` turns off the DNS part, and the
lease file path must be writable (`/var/lib/misc` often does not exist):

```
dnsmasq --interface=vxlan4000 --bind-dynamic --port=0 \
  --dhcp-range=10.102.0.10,10.102.0.20,12h \
  --dhcp-leasefile=/run/dnsmasq-vxlan4000.leases \
  --pid-file=/run/dnsmasq-vxlan4000.pid
```

Client with `dhcpcd`, after the `ip link add` and `ip link set ... up` commands of its
mode (the lease takes about 10 seconds):

```
dhcpcd -4 vxlan4000
dhcpcd -4 -k vxlan4000      # stop it and release the address
```

Client with NetworkManager. This creates the interface and runs NetworkManager's own DHCP
client, and survives a reboot. Unicast or listen client:

```
nmcli connection add type vxlan con-name vxlan4000 ifname vxlan4000 \
  vxlan.id 4000 vxlan.remote 203.0.113.10 vxlan.destination-port 4789 \
  ipv4.method auto ipv6.method disabled
```

Multicast client:

```
nmcli connection add type vxlan con-name vxlan3000 ifname vxlan3000 \
  vxlan.id 3000 vxlan.remote 239.1.1.1 vxlan.parent eth1 vxlan.destination-port 4789 \
  ipv4.method auto ipv6.method disabled
```

Remove a connection with `nmcli connection delete <name>`. In listen mode, DHCP works for
clients that do not set the DHCP broadcast flag (`dhcpcd` and NetworkManager worked).

## Troubleshooting

- The VXLAN interface is never created (multicast, module): no underlay `.network` file
  lists it with `VXLAN=<name>`. The module adds that line to `<device>`'s file (see
  `networkctl cat <device>`).
- Multicast: no traffic between peers. Check `ip maddr show dev <device>` on both sides,
  and that the underlay passes multicast (switch IGMP snooping needs a querier).
- Frames leave but nothing comes back: check the host firewall allows UDP 4789.
