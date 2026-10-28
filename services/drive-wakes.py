"""drive-wakes: what spun the storage disks up, from the journal.

Reads drive-wake-trace (every first disk request after a quiet spell, with
the processes that asked the mergerfs pools for something just before) and
check-drive-status (spin-downs). A request is a wake when the disk was spun
down in between.

  drive-wakes [--since WHEN] [--until WHEN]   (journalctl times; default: today)
"""

import argparse
import json
import os
import subprocess
import sys
from collections import Counter
from datetime import datetime

# FUSE opcodes (linux/fuse.h) that matter here.
FUSE_OPS = {
    1: "lookup",
    3: "getattr",
    4: "setattr",
    9: "mkdir",
    10: "unlink",
    11: "rmdir",
    12: "rename",
    14: "open",
    15: "read",
    16: "write",
    17: "statfs",
    18: "release",
    20: "fsync",
    22: "getxattr",
    25: "flush",
    27: "opendir",
    28: "readdir",
    29: "releasedir",
    35: "create",
    39: "ioctl",
    40: "poll",
    43: "fallocate",
    44: "readdirplus",
    45: "rename",
    52: "statx",
}


def fields(line):
    """'key=value key=value ...' -> dict (the last field may hold spaces)."""
    out = {}
    for part in line.split():
        if "=" in part:
            key, value = part.split("=", 1)
            out[key] = value
    return out


def unit_of(cgroup):
    """unified:/system.slice/plex.service -> plex.service"""
    path = cgroup.split(":", 1)[-1].rstrip("/")
    name = path.rsplit("/", 1)[-1]
    if not name:
        return "kernel"
    if name.startswith("session-") and name.endswith(".scope"):
        return "a login session (" + name + ")"
    return name


def journal(since, until):
    cmd = [
        "journalctl",
        "-o",
        "json",
        "--no-pager",
        "-u",
        "drive-wake-trace",
        "-u",
        "check-drive-status",
    ]
    cmd += ["--since", since] + (["--until", until] if until else [])
    # An argument list, no shell; since/until are the caller's own journalctl times.
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)  # noqa: S603
    for line in proc.stdout.splitlines():
        entry = json.loads(line)
        message = entry.get("MESSAGE")
        if isinstance(message, str):
            yield int(entry["__REALTIME_TIMESTAMP"]) / 1e6, entry.get("_SYSTEMD_UNIT", ""), message


def device_ids(paths):
    """Configured disk path (by-id or /dev/sdX) -> 'major:minor'."""
    ids = {}
    for path in paths:
        try:
            st = os.stat(os.path.realpath(path))
            ids[path] = f"{os.major(st.st_rdev)}:{os.minor(st.st_rdev)}"
        except OSError:
            pass
    return ids


def duration(seconds):
    seconds = int(seconds)
    if seconds >= 3600:
        return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"
    if seconds >= 60:
        return f"{seconds // 60}m{seconds % 60:02d}s"
    return f"{seconds}s"


def main():
    parser = argparse.ArgumentParser(description="What spun the storage disks up.")
    parser.add_argument("--since", default="today")
    parser.add_argument("--until")
    args = parser.parse_args()

    ids = device_ids(os.environ.get("DRIVES", "").split())
    spin_downs = {}  # 'major:minor' -> [time, ...]
    events = []  # io-after-quiet events, each with its pool requests
    for t, unit, message in journal(args.since, args.until):
        if unit.startswith("check-drive-status") and ": spinning down after" in message:
            device = message.split(":", 1)[0]
            spin_downs.setdefault(ids.get(device, device), []).append(t)
        elif message.startswith("io-after-quiet "):
            events.append({"t": t, **fields(message), "requests": []})
        elif message.startswith("pool-request ") and events:
            events[-1]["requests"].append(fields(message))

    if not events:
        print(
            f"No disk requests after a quiet spell since {args.since} (is drive-wake-trace running?)."
        )
        return

    wakes = Counter()
    print(f"Storage disk activity after a quiet spell, since {args.since}:\n")
    for event in events:
        t, quiet = event["t"], int(event["quiet"])
        downs = spin_downs.get(event["dev"], [])
        woke = any(t - quiet < d <= t for d in downs)
        requests = sorted(event["requests"], key=lambda r: int(r["ms_before"]))
        if requests:
            first = requests[0]
            cause = unit_of(first["cgroup"])
            detail = f"{first['comm']}, {FUSE_OPS.get(int(first['op']), 'op ' + first['op'])} {int(first['ms_before']) / 1000:.1f}s before"
        else:
            cause = unit_of(event["cgroup"])
            detail = (
                f"{event['comm']}, {'write' if 'W' in event['rw'] else 'read'} straight to the disk"
            )
        when = datetime.fromtimestamp(t).strftime("%a %H:%M:%S")
        what = (
            f"WOKE after {duration(quiet)} quiet"
            if woke
            else f"kept spinning ({duration(quiet)} quiet)"
        )
        print(f"{when}  {what:<28} {cause}  ({detail})")
        others = sorted({unit_of(r["cgroup"]) for r in requests[1:]} - {cause})
        if others:
            print(f"{'':<39} also asking the pool then: {', '.join(others)}")
        if woke:
            wakes[cause] += 1

    print()
    total = sum(wakes.values())
    print(f"{total} wake{'s' if total != 1 else ''}" + (":" if total else "."))
    for cause, count in wakes.most_common():
        print(f"  {count:>3}  {cause}")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
