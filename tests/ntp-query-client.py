"""Sends one NTP request to a server and prints whether it answered.

    iface=eth1 server=192.0.2.1 reply=yes
    iface=eth1 server=192.0.2.1 reply=no

The client first puts an address from the server's subnet on the interface (the
server's address with the last octet replaced), so the request leaves through
that interface.

usage: ntp-query-client <interface> <server-ip>
"""

import socket
import subprocess
import sys


def main():
    interface, server = sys.argv[1], sys.argv[2]
    own = ".".join(server.split(".")[:3] + ["77"])
    subprocess.run(["ip", "addr", "add", own + "/24", "dev", interface], check=True)
    subprocess.run(["ip", "link", "set", interface, "up"], check=True)

    # 48-byte client request: leap indicator 0, version 4, mode 3 (client).
    request = b"\x23" + b"\0" * 47
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode())
    sock.bind((own, 0))
    sock.settimeout(3)

    reply = "no"
    for _attempt in range(2):
        sock.sendto(request, (server, 123))
        try:
            data, _addr = sock.recvfrom(1024)
            if len(data) >= 48:
                reply = "yes"
                break
        except socket.timeout:
            continue
    print("iface=%s server=%s reply=%s" % (interface, server, reply))


main()
