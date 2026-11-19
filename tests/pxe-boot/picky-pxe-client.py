"""A PXE client that reads the boot file name the way picky firmware does.

QEMU's firmware (OVMF, iPXE) reads DHCP option 67 by its length field, so the
router's offers always work for it. Some real UEFI firmware ignores the length
and copies the value up to the first NUL byte instead: when the option is not
NUL-terminated (and Kea strips a trailing NUL from string options) it runs into
the DHCP END marker and asks TFTP for "bootx64.efi\\xff" (PXE-E23).

This script does DISCOVER -> picks the boot file like that firmware -> TFTP RRQ,
and fails if the server answers with an error. It never completes the DHCP
exchange (no REQUEST): the offer is all the boot file lookup needs.

usage: picky-pxe-client <interface> <pxe-arch>   (arch: 0 = BIOS, 7 = UEFI x64)
"""

import random
import socket
import struct
import subprocess
import sys

MAGIC_COOKIE = b"\x63\x82\x53\x63"
HEADER_LENGTH = 240  # fixed BOOTP header plus the magic cookie


def discover(mac, arch, xid):
    packet = struct.pack(
        "!BBBBIHH4s4s4s4s16s64s128s",
        1, 1, 6, 0, xid, 0, 0x8000,
        b"\0" * 4, b"\0" * 4, b"\0" * 4, b"\0" * 4,
        mac + b"\0" * 10, b"\0" * 64, b"\0" * 128,
    )
    vendor_class = ("PXEClient:Arch:%05d:UNDI:002001" % arch).encode()
    options = b"".join([
        bytes([53, 1, 1]),
        bytes([55, 5, 1, 3, 6, 66, 67]),
        bytes([60, len(vendor_class)]), vendor_class,
        bytes([93, 2]), struct.pack("!H", arch),
        bytes([94, 3, 1, 2, 1]),
        bytes([255]),
    ])
    return packet + MAGIC_COOKIE + options


def options_of(packet):
    """Yields (code, offset of the value, declared length) for each option."""
    pos = HEADER_LENGTH
    while pos < len(packet):
        code = packet[pos]
        if code == 255:
            return
        if code == 0:
            pos += 1
            continue
        length = packet[pos + 1]
        yield code, pos + 2, length
        pos += 2 + length


def message_type(packet):
    for code, start, _length in options_of(packet):
        if code == 53:
            return packet[start]
    return None


def picky_boot_file(packet):
    """The boot file as picky firmware reads it."""
    for code, start, _length in options_of(packet):
        if code == 67:
            # Ignores the declared length: copies up to the first NUL.
            return packet[start:].split(b"\0", 1)[0]
    # No option 67: the BOOTP file header field, a C string at offset 108.
    return packet[108:236].split(b"\0", 1)[0]


def receive_offer(interface, mac, arch):
    xid = random.getrandbits(32)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode())
    sock.bind(("0.0.0.0", 68))
    sock.settimeout(5)
    for _attempt in range(5):
        sock.sendto(discover(mac, arch, xid), ("255.255.255.255", 67))
        try:
            while True:
                packet, _addr = sock.recvfrom(2048)
                if packet[4:8] == struct.pack("!I", xid) and message_type(packet) == 2:
                    return packet
        except socket.timeout:
            continue
    sys.exit("no DHCP offer received")


def tftp_first_reply(server, name):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(5)
    sock.sendto(b"\0\x01" + name + b"\0octet\0", (server, 69))
    reply, _addr = sock.recvfrom(2048)
    opcode = struct.unpack("!H", reply[:2])[0]
    if opcode == 3:
        return "OK"
    return "ERROR %r" % reply[4:].split(b"\0", 1)[0]


def main():
    interface, arch = sys.argv[1], int(sys.argv[2])
    mac = bytes([0x52, 0x54, 0x00, 0xee, 0x00, arch])
    # Firmware starts with no address on the interface and applies no
    # reverse-path filter: the offer comes from a subnet the client has no
    # route to. The kernel uses the stricter of the "all" and per-interface
    # settings, so both are cleared.
    for scope in ("all", interface):
        with open("/proc/sys/net/ipv4/conf/%s/rp_filter" % scope, "w") as handle:
            handle.write("0")
    # Firmware starts with no address on the interface.
    subprocess.run(["ip", "addr", "flush", "dev", interface], check=True)
    subprocess.run(["ip", "link", "set", interface, "up"], check=True)
    packet = receive_offer(interface, mac, arch)

    your_ip = socket.inet_ntoa(packet[16:20])
    next_server = socket.inet_ntoa(packet[20:24])
    # Needs an address to send from, as real firmware configures the offered one.
    subprocess.run(["ip", "addr", "flush", "dev", interface], check=True)
    subprocess.run(["ip", "addr", "add", your_ip + "/24", "dev", interface], check=True)
    subprocess.run(["ip", "link", "set", interface, "up"], check=True)

    name = picky_boot_file(packet)
    result = tftp_first_reply(next_server, name)
    print("arch=%d boot_file=%r tftp=%s" % (arch, name, result))
    if result != "OK":
        sys.exit(1)


main()
