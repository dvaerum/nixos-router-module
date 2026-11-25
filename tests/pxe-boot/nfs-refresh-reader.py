# Stands in for an installer reading its ISO over NFS: keeps one file handle
# open for the whole run and also re-opens the file every round. Any error,
# or data other than expected, is logged; a refresh that unexports or
# remounts this ISO shows up there as "Stale file handle".
#
# usage: nfs-refresh-reader <file> <expected-prefix> <error-log> <counter-file>
import os
import sys
import time

path, expected, error_log, counter_file = sys.argv[1:5]
expected = expected.encode()


def record(what):
    with open(error_log, "a") as f:
        f.write(f"{time.time():.1f} {what}\n")


held = os.open(path, os.O_RDONLY)
rounds = 0
while True:
    try:
        if os.pread(held, len(expected), 0) != expected:
            record("held handle returned unexpected data")
        with open(path, "rb") as f:
            if f.read(len(expected)) != expected:
                record("fresh open returned unexpected data")
        rounds += 1
        with open(counter_file, "w") as f:
            f.write(str(rounds))
    except OSError as e:
        record(f"{type(e).__name__}: {e}")
    time.sleep(0.2)
