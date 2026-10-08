# VXLAN: modes, and getting an address with DHCP

A VXLAN interface connects to its peers in one of three modes. Set exactly one of
`remote`, `group` or `listen` on each `vxlanInterfaces` entry.

| Mode | Use it when | Set |
|------|-------------|-----|
| [unicast](#unicast) | a fixed pair of routers | `remote` = the other end |
| [multicast](#multicast) | several routers share one VXLAN on a network that carries multicast | `group` and `device` |
| [listen](#listen-hub) | one hub, clients connect to it, no list of clients | hub: `listen`; clients: `remote` = hub |

Every mode section has the same parts: the module config, the same setup by hand
(`ip` commands, or `nmcli`), and how to check it. DHCP is shared by all modes and has
its own [section](#dhcp-on-a-vxlan-any-mode).

## Before you start

- All peers of one VXLAN use the same `vni`.
- Manage each interface with one method: this module, `ip` commands (plus `dhcpcd` and
  `dnsmasq` for DHCP), or `nmcli`. Do not mix them on the same interface.
- `ip` commands are gone after a reboot. NetworkManager saves `nmcli` connections.
- The encapsulated traffic is UDP port 4789 (the `destinationPort` option; `dstport` in
  the commands). This module turns the host firewall off, so a host running it needs no
  rule. Any other host with a firewall must allow UDP 4789.
- The addresses, interface names and VNIs below are examples. The tunnel is not
  encrypted.

## Unicast

Two routers, each pointing at the other.

```text
 r1 ---- UDP 4789 ---- r2        (r1: remote = r2, r2: remote = r1)
```

### With this module

```nix
my.router.vxlanInterfaces.vxlan1000 = {
  vni = 1000;
  remote = "172.20.1.1";    # static, routable IP of the other end
  dhcp.static.ip-address = "10.100.0.2/30";
};
```

The other end uses `remote = "<this router's IP>"` and `10.100.0.1/30`.

### By hand

```sh
ip link add vxlan1000 type vxlan id 1000 remote 172.20.1.1 dstport 4789
ip link set vxlan1000 up
ip addr add 10.100.0.2/30 dev vxlan1000
```

With NetworkManager instead:

```sh
nmcli connection add type vxlan con-name vxlan1000 ifname vxlan1000 \
  vxlan.id 1000 vxlan.remote 172.20.1.1 vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses 10.100.0.2/30 ipv6.method disabled
```

### Check

```sh
ip -d link show vxlan1000   # ... vxlan id 1000 remote 172.20.1.1 ... dstport 4789
```

## Multicast

Any number of routers join one multicast group. Unknown and broadcast traffic goes to the
group, so there is no list of peers.

```text
   r1        r2        r3
   |         |         |
  eth1      eth1      eth1        each device joins group 239.1.1.1
   |         |         |
 ==============================    underlay network
```

### With this module

```nix
my.router.vxlanInterfaces.vxlan3000 = {
  vni = 3000;
  group = "239.1.1.1";      # 224.0.0.0 - 239.255.255.255
  device = "eth1";          # underlay interface that joins the group
  dhcp.static.ip-address = "10.101.0.2/24";
};
```

`group` and `device` are set together. `device` must be a `configInterface` or
`bridgeInterfaces` entry. Each peer uses its own address.

### By hand

```sh
ip link add vxlan3000 type vxlan id 3000 group 239.1.1.1 dev eth1 dstport 4789
ip link set vxlan3000 up
ip addr add 10.101.0.2/24 dev vxlan3000
```

With NetworkManager instead (`vxlan.remote` is the group, `vxlan.parent` is the underlay
interface):

```sh
nmcli connection add type vxlan con-name vxlan3000 ifname vxlan3000 \
  vxlan.id 3000 vxlan.remote 239.1.1.1 vxlan.parent eth1 vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses 10.101.0.2/24 ipv6.method disabled
```

### Check

```sh
ip -d link show vxlan3000   # ... vxlan id 3000 group 239.1.1.1 dev eth1 ... dstport 4789
ip maddr show dev eth1      # ... inet  239.1.1.1
```

### Routed underlay

On one shared network segment the group join is all that is needed. If there are routers
between the peers, they must route the group; the expected setup is `multicast = true;`
on the underlay interface so `pimd` runs on it. This module does not do that for you, and
it has not been tested here.

## Listen (hub)

The hub has no list of clients. It learns each client's address from the frames the
client sends, and replies to it. Clients are ordinary unicast VXLANs.

```text
 client A (remote = hub) ---\
                             >--- hub (listen)    learns A and B from their frames
 client B (remote = hub) ---/
```

### With this module

Hub:

```nix
my.router.vxlanInterfaces.vxlan4000 = {
  vni = 4000;
  listen = true;
  local = "203.0.113.10";                 # optional: address to bind (default: all)
  dhcp.static.ip-address = "10.102.0.1/24";
};
```

Client:

```nix
my.router.vxlanInterfaces.vxlan4000 = {
  vni = 4000;
  remote = "203.0.113.10";                # the hub
  dhcp.static.ip-address = "10.102.0.2/24";
};
```

### By hand

Hub (no `remote`, which is what makes it a hub):

```sh
ip link add vxlan4000 type vxlan id 4000 local 203.0.113.10 dstport 4789
ip link set vxlan4000 up
ip addr add 10.102.0.1/24 dev vxlan4000
```

Client:

```sh
ip link add vxlan4000 type vxlan id 4000 remote 203.0.113.10 dstport 4789
ip link set vxlan4000 up
ip addr add 10.102.0.2/24 dev vxlan4000
```

With NetworkManager instead, hub and client:

```sh
nmcli connection add type vxlan con-name vxlan4000 ifname vxlan4000 \
  vxlan.id 4000 vxlan.local 203.0.113.10 vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses 10.102.0.1/24 ipv6.method disabled

nmcli connection add type vxlan con-name vxlan4000 ifname vxlan4000 \
  vxlan.id 4000 vxlan.remote 203.0.113.10 vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses 10.102.0.2/24 ipv6.method disabled
```

### Check

A client shows up on the hub only after it has sent something.

```sh
ip -d link show vxlan4000      # hub: "vxlan id 4000 local ..." with no remote or group
bridge fdb show dev vxlan4000  # hub: "<client mac> dst <client ip>"
```

### Limits

- The hub cannot start talking to a client it has not heard from. The client must send
  first (its DHCP request, or a ping).
- Idle clients are forgotten after 300 seconds; the client must send again.
- DHCP works for clients that do not set the DHCP broadcast flag. `dhcpcd`,
  NetworkManager and systemd-networkd worked here.

### Client behind NAT

VXLAN sends nothing when idle, so a NAT forgets the mapping after its UDP timeout (often
30 to 120 seconds). Keep a ping to the hub running through the tunnel, more often than
that. As a background process:

```sh
ping -i 20 -q 10.102.0.1 >/dev/null &
```

Or as a systemd unit that restarts itself (it lasts until reboot):

```sh
systemd-run --unit=vxlan-keepalive --property=Restart=always ping -i 20 -q 10.102.0.1
systemctl stop vxlan-keepalive      # to stop it
```

This is only a workaround and has not been tested behind a real NAT. The hub replies to
the standard VXLAN port, not the port the NAT mapped for the client, so some NATs will
still break it. For clients behind NAT, run VXLAN over WireGuard instead: point `remote`
at the hub's WireGuard address.

## DHCP on a VXLAN (any mode)

One peer is the DHCP server, the others are clients. The examples use the listen-mode
names (`vxlan4000`, `10.102.0.0/24`, hub `203.0.113.10`); replace them for your VXLAN.

### With this module

Server: `dhcp.server.address = "10.102.0.1/24";` (instead of `dhcp.static`).
Clients: `dhcp.client = { };` (instead of `dhcp.static`). Add `useRoutes = true;` inside
the braces to also accept classless static routes; see the `dhcp.client` option.

### By hand: server

The VXLAN needs an address first (`ip addr add ...` as above). `--port=0` turns off the
DNS part. The lease file path must be writable; `/var/lib/misc` often does not exist.

```sh
dnsmasq --interface=vxlan4000 --bind-dynamic --port=0 \
  --dhcp-range=10.102.0.10,10.102.0.20,12h \
  --dhcp-leasefile=/run/dnsmasq-vxlan4000.leases \
  --pid-file=/run/dnsmasq-vxlan4000.pid
```

### By hand: client with `dhcpcd`

Create and bring up the interface as in its mode section, but skip `ip addr add`. The
lease takes about 10 seconds.

```sh
dhcpcd -4 vxlan4000
dhcpcd -4 -k vxlan4000      # stop it and release the address
```

### By hand: client with NetworkManager

This creates the interface and runs NetworkManager's own DHCP client. Unicast or listen
client:

```sh
nmcli connection add type vxlan con-name vxlan4000 ifname vxlan4000 \
  vxlan.id 4000 vxlan.remote 203.0.113.10 vxlan.destination-port 4789 \
  ipv4.method auto ipv6.method disabled
```

Multicast client (`vxlan.remote` is the group, `vxlan.parent` the underlay interface):

```sh
nmcli connection add type vxlan con-name vxlan3000 ifname vxlan3000 \
  vxlan.id 3000 vxlan.remote 239.1.1.1 vxlan.parent eth1 vxlan.destination-port 4789 \
  ipv4.method auto ipv6.method disabled
```

Remove a connection with `nmcli connection delete <name>`.

## Troubleshooting

- **Any mode:** frames leave but nothing comes back. Check that the host firewall allows
  UDP 4789.
- **Multicast:** no traffic between peers. Check `ip maddr show dev <device>` on both
  sides, and that the underlay passes multicast (switch IGMP snooping needs a querier).
- **Multicast, with this module:** the VXLAN interface is never created. No underlay
  `.network` file lists it with `VXLAN=<name>`; the module adds that line to `<device>`'s
  file (see `networkctl cat <device>`).
- **Listen:** the hub cannot reach a client. The client has to send first; see
  [Limits](#limits).
