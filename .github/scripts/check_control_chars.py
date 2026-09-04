#!/usr/bin/env python3
"""Fail if any script contains a stray control character.

cmd.exe reads a stray BEL or backspace as part of a path, so a bad
escape introduced by an edit fails at runtime rather than at parse
time. This caught a corrupted api_key.txt path once already.
"""
import io
import subprocess
import sys

LEGITIMATE = (0x09, 0x0a, 0x0d)  # tab, LF, CR


def main():
    files = subprocess.check_output(
        ["git", "ls-files", "*.sh", "*.bat", "*.ps1"]
    ).decode().split()

    bad = []
    for path in files:
        raw = io.open(path, "rb").read()
        for i, byte in enumerate(raw):
            if byte < 0x20 and byte not in LEGITIMATE:
                line = raw[:i].count(b"\n") + 1
                bad.append("%s:%d contains byte %s" % (path, line, hex(byte)))

    if bad:
        print("FAIL")
        print("\n".join(bad))
        return 1

    print("No stray control characters in %d scripts" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
