# VXLAN listen mode (hub and clients)

One host acts as a hub. Clients point at it. The hub needs no list of clients: it
learns each client's address from the frames the client sends, and replies to it.

```
 client A (remote = hub) --\
                            >-- hub (listen = true) learns A, B from their frames
 client B (remote = hub) --/
```

VXLAN is stateless UDP, so there is no real "connection" and no keepalive.

## With this module

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
  dhcp.client = { };         # get an address from the hub's DHCP server
};
```

Set exactly one of `remote`, `group` or `listen` on each VXLAN. The module turns the
firewall off, so UDP 4789 needs no extra rule here.

## By hand (without this module)

Hub (UDP port 4789 must be reachable; open it if you run a firewall):

```
ip link add vxlan4000 type vxlan id 4000 local 203.0.113.10 dstport 4789
ip link set vxlan4000 up
ip addr add 10.102.0.1/24 dev vxlan4000
```

Optional DHCP server for the clients, for example dnsmasq with
`interface=vxlan4000`, `bind-dynamic` and `dhcp-range=10.102.0.10,10.102.0.20,12h`.

Client (links to the hub, then gets an address with the systemd DHCP client):

```
ip link add vxlan4000 type vxlan id 4000 remote 203.0.113.10 dstport 4789
ip link set vxlan4000 up
```

Save as `/etc/systemd/network/40-vxlan4000.network`, then run `networkctl reload`:

```
[Match]
Name=vxlan4000

[Network]
DHCP=ipv4
LinkLocalAddressing=no
```

Check it. On the hub, a client shows up only after it has sent something:

```
ip -d link show vxlan4000      # hub: "vxlan id 4000 local ..." with no remote or group
bridge fdb show dev vxlan4000  # hub: "<client mac> dst <client ip>"
ip -4 addr show vxlan4000      # client: the leased address
```

## Client behind NAT: keep the tunnel alive

VXLAN sends nothing when idle, so a NAT forgets the mapping after its UDP timeout
(often 30 to 120 seconds). The hub also forgets idle clients after 300 seconds.
Keep a ping to the hub running through the tunnel, more often than the NAT timeout:

```
ping -i 20 -q 10.102.0.1 >/dev/null &
```

To keep it running across reboots, save as `/etc/systemd/system/vxlan-keepalive.service`:

```
[Unit]
Description=Keep the VXLAN tunnel alive through NAT
After=network-online.target

[Service]
ExecStart=/usr/bin/env ping -i 20 -q 10.102.0.1
Restart=always

[Install]
WantedBy=multi-user.target
```

This is only a workaround. The hub replies to the standard VXLAN port, not the port the
NAT mapped for the client, so some NATs still break it. For clients behind NAT, run
VXLAN over WireGuard instead: point `remote` at the hub's WireGuard address.

## Limits

- The hub cannot start talking to a client it has not heard from. The client must send
  first (its DHCP request, or a ping).
- Idle clients are forgotten after 300 seconds; the client must send again.
- DHCP works for clients that do not set the DHCP broadcast flag (systemd-networkd
  does not).
- The tunnel is not encrypted.

For several routers sharing one VXLAN on a multicast-capable network, see
[vxlan-multicast.md](./vxlan-multicast.md).
