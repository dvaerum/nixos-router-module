"""Asks a DHCP server to confirm an address it has never leased.

Sends a DHCPREQUEST in the INIT-REBOOT state (a requested address, no server
identifier) on one interface and prints how the server reacts:

    iface=eth1 reply=NAK     an authoritative server refuses the stale address
    iface=eth1 reply=none    a non-authoritative server stays silent

usage: dhcp-unknown-renewal-client <interface> <requested-ip>
"""

import random
import socket
import struct
import subprocess
import sys

MAGIC_COOKIE = b"\x63\x82\x53\x63"
HEADER_LENGTH = 240  # fixed BOOTP header plus the magic cookie
TYPES = {2: "OFFER", 5: "ACK", 6: "NAK"}


def request(mac, xid, requested_ip):
    packet = struct.pack(
        "!BBBBIHH4s4s4s4s16s64s128s",
        1, 1, 6, 0, xid, 0, 0x8000,
        b"\0" * 4, b"\0" * 4, b"\0" * 4, b"\0" * 4,
        mac + b"\0" * 10, b"\0" * 64, b"\0" * 128,
    )
    options = b"".join([
        bytes([53, 1, 3]),
        bytes([50, 4]), socket.inet_aton(requested_ip),
        bytes([55, 3, 1, 3, 6]),
        bytes([255]),
    ])
    return packet + MAGIC_COOKIE + options


def message_type(packet):
    pos = HEADER_LENGTH
    while pos < len(packet) and packet[pos] != 255:
        if packet[pos] == 0:
            pos += 1
            continue
        if packet[pos] == 53:
            return packet[pos + 2]
        pos += 2 + packet[pos + 1]
    return None


def main():
    interface, requested_ip = sys.argv[1], sys.argv[2]
    mac = bytes([0x52, 0x54, 0x00, 0xdd, 0x00, 0x01])

    # Like a client that has just booted: no address yet, and no reverse-path
    # filter (the reply comes from a subnet it has no route to). The kernel
    # uses the stricter of the "all" and per-interface settings.
    for scope in ("all", interface):
        with open("/proc/sys/net/ipv4/conf/%s/rp_filter" % scope, "w") as handle:
            handle.write("0")
    subprocess.run(["ip", "addr", "flush", "dev", interface], check=True)
    subprocess.run(["ip", "link", "set", interface, "up"], check=True)

    xid = random.getrandbits(32)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode())
    sock.bind(("0.0.0.0", 68))
    sock.settimeout(3)

    reply = "none"
    for _attempt in range(2):
        sock.sendto(request(mac, xid, requested_ip), ("255.255.255.255", 67))
        try:
            while True:
                packet, _addr = sock.recvfrom(2048)
                if packet[4:8] == struct.pack("!I", xid):
                    reply = TYPES.get(message_type(packet), "other")
                    break
        except socket.timeout:
            continue
        break
    print("iface=%s reply=%s" % (interface, reply))


main()
