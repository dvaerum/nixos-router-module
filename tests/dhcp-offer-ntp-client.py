"""Does a DHCP DISCOVER on one interface and prints the NTP servers in the offer.

Asks for NTP servers (option 42) in its parameter request list, as real
clients do, and prints what the server's DHCPOFFER carries:

    iface=eth1 ntp=192.0.2.1             one or more servers
    iface=eth1 ntp=none                  no option 42 in the offer

usage: dhcp-offer-ntp-client <interface>
"""

import random
import socket
import struct
import subprocess
import sys

MAGIC_COOKIE = b"\x63\x82\x53\x63"
HEADER_LENGTH = 240  # fixed BOOTP header plus the magic cookie


def discover(mac, xid):
    packet = struct.pack(
        "!BBBBIHH4s4s4s4s16s64s128s",
        1, 1, 6, 0, xid, 0, 0x8000,
        b"\0" * 4, b"\0" * 4, b"\0" * 4, b"\0" * 4,
        mac + b"\0" * 10, b"\0" * 64, b"\0" * 128,
    )
    options = b"".join([
        bytes([53, 1, 1]),
        bytes([55, 4, 1, 3, 6, 42]),
        bytes([255]),
    ])
    return packet + MAGIC_COOKIE + options


def options_of(packet):
    """Yields (code, value) for each option."""
    pos = HEADER_LENGTH
    while pos < len(packet):
        code = packet[pos]
        if code == 255:
            return
        if code == 0:
            pos += 1
            continue
        length = packet[pos + 1]
        yield code, packet[pos + 2:pos + 2 + length]
        pos += 2 + length


def main():
    interface = sys.argv[1]
    mac = bytes([0x52, 0x54, 0x00, 0xcc, 0x00, 0x01])

    # Like a client that has just booted: no address yet, and no reverse-path
    # filter (the offer comes from a subnet it has no route to). The kernel
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

    for _attempt in range(4):
        sock.sendto(discover(mac, xid), ("255.255.255.255", 67))
        try:
            while True:
                packet, _addr = sock.recvfrom(2048)
                if packet[4:8] != struct.pack("!I", xid):
                    continue
                servers = [
                    socket.inet_ntoa(value[i:i + 4])
                    for code, value in options_of(packet) if code == 42
                    for i in range(0, len(value), 4)
                ]
                print("iface=%s ntp=%s" % (interface, ",".join(servers) or "none"))
                return
        except socket.timeout:
            continue
    sys.exit("no DHCP offer received on " + interface)


main()
