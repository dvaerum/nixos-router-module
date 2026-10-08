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

- Replace every `<placeholder>` in the examples; see [Placeholders](#placeholders).
- All peers of one VXLAN use the same `<vni>`.
- Manage each interface with one method: this module, `ip` commands (plus `dhcpcd` and
  `dnsmasq` for DHCP), or `nmcli`. Do not mix them on the same interface.
- `ip` commands are gone after a reboot. NetworkManager saves `nmcli` connections.
- The encapsulated traffic is UDP port 4789 (the `destinationPort` option, `dstport` in
  the commands). It is the standard VXLAN port; if you change it, change it on every
  peer. This module turns the host firewall off, so a host running it needs no rule. Any
  other host with a firewall must allow that UDP port.
- The tunnel is not encrypted.

## Placeholders

| Placeholder | Meaning | What you can write | Examples |
|-------------|---------|--------------------|----------|
| `<ifname>` | Name of the VXLAN interface (also used as the `nmcli` connection name) | 1 to 15 letters, digits, `.`, `_` or `-` | `vxlan1000`, `vxlan-office` |
| `<vni>` | VXLAN Network Identifier, one per VXLAN | a number from 0 to 16777215, the same on every peer | `1000`, `42` |
| `<remote-ip>` | IP address of the other end (unicast) or of the hub (listen client) | a static, routable IP address, not a hostname | `172.20.1.1`, `203.0.113.10` |
| `<local-ip>` | An IP address of this host to send from and listen on | an address that is configured on this host | `203.0.113.10` |
| `<group>` | Multicast group all peers join | an address from 224.0.0.0 to 239.255.255.255; use 239.0.0.0 to 239.255.255.255 for private use | `239.1.1.1` |
| `<underlay-if>` | Interface that carries the VXLAN traffic and joins the group | in the module a `configInterface` or `bridgeInterfaces` entry; with commands any interface | `eth1`, `br0`, `enp3s0` |
| `<vxlan-ip>` | This peer's address inside the VXLAN | an unused address in the VXLAN's subnet, different on every peer | `10.100.0.2`, `10.101.0.2` |
| `<prefix>` | Prefix length of the VXLAN's subnet | a number: 24 fits about 250 hosts, 30 fits a two-router link | `24`, `30` |
| `<hub-vxlan-ip>` | The hub's address inside the VXLAN | an address in the same subnet as the clients | `10.102.0.1` |
| `<server-ip>` | The DHCP server's address inside the VXLAN (the hub, in listen mode) | an address in the VXLAN's subnet | `10.102.0.1` |
| `<range-start>`, `<range-end>` | First and last address the DHCP server hands out | addresses in the VXLAN's subnet, not including `<server-ip>` | `10.102.0.10`, `10.102.0.20` |
| `<lease-time>` | How long a DHCP lease lasts | a number of seconds, minutes (`45m`), hours (`12h`) or `infinite` | `12h`, `1h` |

## Unicast

Two routers, each pointing at the other.

```text
 r1 ---- UDP 4789 ---- r2        (r1: remote = r2, r2: remote = r1)
```

### With this module

```nix
my.router.vxlanInterfaces.<ifname> = {
  vni = <vni>;
  remote = "<remote-ip>";
  dhcp.static.ip-address = "<vxlan-ip>/<prefix>";
};
```

The other end uses this router's IP as its `remote`, and its own `<vxlan-ip>` in the same
subnet.

### By hand

```sh
ip link add <ifname> type vxlan id <vni> remote <remote-ip> dstport 4789
ip link set <ifname> up
ip addr add <vxlan-ip>/<prefix> dev <ifname>
```

With NetworkManager instead:

```sh
nmcli connection add type vxlan con-name <ifname> ifname <ifname> \
  vxlan.id <vni> vxlan.remote <remote-ip> vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses <vxlan-ip>/<prefix> ipv6.method disabled
```

### Check

```sh
ip -d link show <ifname>   # ... vxlan id <vni> remote <remote-ip> ... dstport 4789
```

## Multicast

Any number of routers join one multicast group. Unknown and broadcast traffic goes to the
group, so there is no list of peers.

```text
   r1        r2        r3        each router's <underlay-if> joins <group>
   |         |         |
 ==============================    underlay network
```

### With this module

```nix
my.router.vxlanInterfaces.<ifname> = {
  vni = <vni>;
  group = "<group>";
  device = "<underlay-if>";
  dhcp.static.ip-address = "<vxlan-ip>/<prefix>";
};
```

`group` and `device` are set together. Each peer uses its own `<vxlan-ip>`.

### By hand

```sh
ip link add <ifname> type vxlan id <vni> group <group> dev <underlay-if> dstport 4789
ip link set <ifname> up
ip addr add <vxlan-ip>/<prefix> dev <ifname>
```

With NetworkManager instead (`vxlan.remote` is the group, `vxlan.parent` is the underlay
interface):

```sh
nmcli connection add type vxlan con-name <ifname> ifname <ifname> \
  vxlan.id <vni> vxlan.remote <group> vxlan.parent <underlay-if> vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses <vxlan-ip>/<prefix> ipv6.method disabled
```

### Check

```sh
ip -d link show <ifname>        # ... vxlan id <vni> group <group> dev <underlay-if> ... dstport 4789
ip maddr show dev <underlay-if> # ... inet  <group>
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
my.router.vxlanInterfaces.<ifname> = {
  vni = <vni>;
  listen = true;
  local = "<local-ip>";                    # optional: address to bind (default: all)
  dhcp.static.ip-address = "<hub-vxlan-ip>/<prefix>";
};
```

Client (`<remote-ip>` is the hub's IP):

```nix
my.router.vxlanInterfaces.<ifname> = {
  vni = <vni>;
  remote = "<remote-ip>";
  dhcp.static.ip-address = "<vxlan-ip>/<prefix>";
};
```

### By hand

Hub (no `remote`, which is what makes it a hub):

```sh
ip link add <ifname> type vxlan id <vni> local <local-ip> dstport 4789
ip link set <ifname> up
ip addr add <hub-vxlan-ip>/<prefix> dev <ifname>
```

Client (`<remote-ip>` is the hub's IP):

```sh
ip link add <ifname> type vxlan id <vni> remote <remote-ip> dstport 4789
ip link set <ifname> up
ip addr add <vxlan-ip>/<prefix> dev <ifname>
```

With NetworkManager instead, hub and client:

```sh
nmcli connection add type vxlan con-name <ifname> ifname <ifname> \
  vxlan.id <vni> vxlan.local <local-ip> vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses <hub-vxlan-ip>/<prefix> ipv6.method disabled

nmcli connection add type vxlan con-name <ifname> ifname <ifname> \
  vxlan.id <vni> vxlan.remote <remote-ip> vxlan.destination-port 4789 \
  ipv4.method manual ipv4.addresses <vxlan-ip>/<prefix> ipv6.method disabled
```

### Check

A client shows up on the hub only after it has sent something.

```sh
ip -d link show <ifname>      # hub: "vxlan id <vni> local <local-ip>" with no remote or group
bridge fdb show dev <ifname>  # hub: one line per client: its MAC address and its IP address
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
ping -i 20 -q <hub-vxlan-ip> >/dev/null &
```

Or as a systemd unit that restarts itself (it lasts until reboot):

```sh
systemd-run --unit=vxlan-keepalive --property=Restart=always ping -i 20 -q <hub-vxlan-ip>
systemctl stop vxlan-keepalive      # to stop it
```

This is only a workaround and has not been tested behind a real NAT. The hub replies to
the standard VXLAN port, not the port the NAT mapped for the client, so some NATs will
still break it. For clients behind NAT, run VXLAN over WireGuard instead: point
`<remote-ip>` at the hub's WireGuard address.

## DHCP on a VXLAN (any mode)

One peer is the DHCP server, the others are clients.

### With this module

Server: `dhcp.server.address = "<server-ip>/<prefix>";` (instead of `dhcp.static`).
Clients: `dhcp.client = { };` (instead of `dhcp.static`). Add `useRoutes = true;` inside
the braces to also accept classless static routes; see the `dhcp.client` option.

### By hand: server

The VXLAN needs an address first (`ip addr add <server-ip>/<prefix> dev <ifname>`). `--port=0`
turns off the DNS part. The lease file path must be writable; `/var/lib/misc` often does
not exist.

```sh
dnsmasq --interface=<ifname> --bind-dynamic --port=0 \
  --dhcp-range=<range-start>,<range-end>,<lease-time> \
  --dhcp-leasefile=/run/dnsmasq-<ifname>.leases \
  --pid-file=/run/dnsmasq-<ifname>.pid
```

### By hand: client with `dhcpcd`

Create and bring up the interface as in its mode section, but skip `ip addr add`. The
lease takes about 10 seconds.

```sh
dhcpcd -4 <ifname>
dhcpcd -4 -k <ifname>      # stop it and release the address
```

### By hand: client with NetworkManager

This creates the interface and runs NetworkManager's own DHCP client. Unicast or listen
client:

```sh
nmcli connection add type vxlan con-name <ifname> ifname <ifname> \
  vxlan.id <vni> vxlan.remote <remote-ip> vxlan.destination-port 4789 \
  ipv4.method auto ipv6.method disabled
```

Multicast client (`vxlan.remote` is the group, `vxlan.parent` the underlay interface):

```sh
nmcli connection add type vxlan con-name <ifname> ifname <ifname> \
  vxlan.id <vni> vxlan.remote <group> vxlan.parent <underlay-if> vxlan.destination-port 4789 \
  ipv4.method auto ipv6.method disabled
```

Remove a connection with `nmcli connection delete <ifname>`.

## Troubleshooting

- **Any mode:** frames leave but nothing comes back. Check that the host firewall allows
  UDP 4789.
- **Multicast:** no traffic between peers. Check `ip maddr show dev <underlay-if>` on both
  sides, and that the underlay passes multicast (switch IGMP snooping needs a querier).
- **Multicast, with this module:** the VXLAN interface is never created. No underlay
  `.network` file lists it with `VXLAN=<ifname>`; the module adds that line to
  `<underlay-if>`'s file (see `networkctl cat <underlay-if>`).
- **Listen:** the hub cannot reach a client. The client has to send first; see
  [Limits](#limits).
