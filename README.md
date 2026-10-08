# Intro

This NixOS module make it easy convert NixOS into a home router and
later I ended up using it at work

I know that there [nixos-router](https://github.com/chayleaf/nixos-router) exists,
but I wanted to use `systemd-network` and
also wanted to have a deeper understanding for how everything works.

**Documentation for NixOS module:** [options](./docs/options.md)


## Current features:

- VLANs
- VXLAN (unicast, multicast, or listening hub; [modes and DHCP](./docs/vxlan-modes-and-dhcp.md))
- Multi-cast
- DHCP server
- PXE Boot (beta)

