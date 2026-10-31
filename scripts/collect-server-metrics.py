#!/usr/bin/env python3
"""Read host counters only; publish an atomic, bounded snapshot for the API."""
import argparse
import datetime
import json
import os
from pathlib import Path
import time


def collect(proc=Path('/proc'), previous=None, clock=time.time, disk=os.statvfs):
    previous = previous if isinstance(previous, dict) else {}
    now = clock()
    memory = {}
    for line in (proc / 'meminfo').read_text().splitlines():
        key, value = line.split(':', 1)
        memory[key] = int(value.split()[0]) * 1024
    cpu = [int(v) for v in (proc / 'stat').read_text().splitlines()[0].split()[1:9]]
    total, idle = sum(cpu), cpu[3] + cpu[4]
    before = previous.get('_sample', {})
    elapsed = now - before.get('time', now)
    ticks = total - before.get('cpu_total', total)
    busy = None if ticks <= 0 or elapsed <= 0 else round(max(0, min(100, (1 - (idle - before.get('cpu_idle', idle)) / ticks) * 100)), 1)
    cores = sum(line.startswith('processor\t') or line.startswith('processor ') for line in (proc / 'cpuinfo').read_text().splitlines()) or os.cpu_count() or 1
    load = [float(v) for v in (proc / 'loadavg').read_text().split()[:3]]
    uptime = float((proc / 'uptime').read_text().split()[0])
    fs = disk('/')
    total_disk, free_disk, available_disk = fs.f_blocks * fs.f_frsize, fs.f_bfree * fs.f_frsize, fs.f_bavail * fs.f_frsize
    ram_total, ram_available = memory['MemTotal'], memory.get('MemAvailable', memory.get('MemFree', 0))
    swap_total, swap_free = memory.get('SwapTotal', 0), memory.get('SwapFree', 0)
    network = [0, 0]
    routes = proc / 'net/route'
    interfaces = {line.split()[0] for line in routes.read_text().splitlines()[1:] if len(line.split()) > 1 and line.split()[1] == '00000000'} if routes.exists() else set()
    for line in (proc / 'net/dev').read_text().splitlines()[2:]:
        name, raw = line.split(':', 1)
        if name.strip() == 'lo' or interfaces and name.strip() not in interfaces or not interfaces and name.strip().startswith(('veth', 'docker', 'br-')):
            continue
        fields = raw.split()
        network[0] += int(fields[0])
        network[1] += int(fields[8])
    rates = [None, None]
    if elapsed > 0 and len(before.get('network', [])) == 2:
        rates = [round((network[i] - before['network'][i]) / elapsed) if network[i] >= before['network'][i] else None for i in range(2)]
    memory_used = max(0, ram_total - ram_available)
    disk_used = max(0, total_disk - free_disk)
    point = {'at': datetime.datetime.fromtimestamp(now, datetime.timezone.utc).isoformat(), 'cpu_percent': busy, 'memory_percent': round(memory_used * 100 / ram_total, 1), 'disk_percent': round(disk_used * 100 / total_disk, 1)}
    cutoff = datetime.datetime.fromtimestamp(now - 3600, datetime.timezone.utc).isoformat()
    history = [p for p in previous.get('history', []) if isinstance(p, dict) and isinstance(p.get('at'), str) and cutoff <= p['at'] <= point['at']][-179:] + [point]
    return {'schema': 1, 'collected_at': point['at'], 'source': 'host', 'uptime_seconds': int(uptime),
            'cpu': {'logical_cores': cores, 'usage_percent': busy, 'load_average': load},
            'memory': {'total_bytes': ram_total, 'used_bytes': memory_used, 'available_bytes': ram_available, 'usage_percent': point['memory_percent'], 'swap_total_bytes': swap_total, 'swap_used_bytes': max(0, swap_total - swap_free)},
            'disk': {'mount': '/', 'total_bytes': total_disk, 'used_bytes': disk_used, 'available_bytes': available_disk, 'usage_percent': point['disk_percent']},
            'network': {'received_bytes_per_second': rates[0], 'sent_bytes_per_second': rates[1]},
            'history': history, '_sample': {'time': now, 'cpu_total': total, 'cpu_idle': idle, 'network': network}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    directory = Path(args.output_dir)
    target = directory / 'metrics.json'
    try:
        previous = json.loads(target.read_text())
    except (OSError, ValueError):
        previous = {}
    snapshot = collect(previous=previous)
    temporary = directory / 'metrics.tmp'
    temporary.write_text(json.dumps(snapshot, separators=(',', ':')) + '\n')
    temporary.chmod(0o644)
    os.replace(temporary, target)


if __name__ == '__main__':
    main()
