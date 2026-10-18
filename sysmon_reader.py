#!/usr/bin/env python3
import time, os, shutil, glob, json, sys

STATE_FILE = "/tmp/macwidgets_sysmon_state.json"

def get_current_counters():
    # CPU
    i, t = 0, 1
    try:
        with open('/proc/stat') as f:
            fields = [float(x) for x in f.readline().strip().split()[1:8]]
        i, t = fields[3] + fields[4], sum(fields)
    except:
        pass

    # Network
    net_bytes = 0
    try:
        with open('/proc/net/dev') as f:
            for line in f:
                if ':' in line:
                    parts = line.split(':')[1].split()
                    if len(parts) >= 9:
                        net_bytes += int(parts[0]) + int(parts[8])
    except:
        pass

    # GPU
    gpu_rc6 = -1
    for p in ['/sys/class/drm/card1/power/rc6_residency_ms', '/sys/class/drm/card0/power/rc6_residency_ms']:
        if os.path.exists(p):
            try:
                with open(p) as f:
                    gpu_rc6 = int(f.read().strip())
                break
            except:
                pass

    return time.time(), i, t, net_bytes, gpu_rc6

def get_sysmon():
    now, curr_idle, curr_total, curr_net, curr_gpu_rc6 = get_current_counters()

    prev_state = None
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                prev_state = json.load(f)
        except:
            pass

    gpu_pct = 0
    if prev_state and "time" in prev_state:
        dt = now - prev_state["time"]
        if 0.5 <= dt <= 10.0:
            d_total = curr_total - prev_state["total"]
            d_idle = curr_idle - prev_state["idle"]
            if d_total > 0:
                cpu_pct = round(max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100)))
            else:
                cpu_pct = 0

            d_net = max(0, curr_net - prev_state["net"])
            net_bytes_sec = d_net / dt

            prev_rc6 = prev_state.get("gpu_rc6", -1)
            if curr_gpu_rc6 >= 0 and prev_rc6 >= 0:
                d_rc6 = curr_gpu_rc6 - prev_rc6
                dt_ms = dt * 1000
                if dt_ms > 0 and d_rc6 >= 0:
                    gpu_pct = max(0, min(100, round(100 - (d_rc6 / dt_ms) * 100)))
        else:
            time.sleep(0.05)
            now2, curr_idle2, curr_total2, curr_net2, curr_gpu_rc6_2 = get_current_counters()
            dt = now2 - now
            d_total = curr_total2 - curr_total
            d_idle = curr_idle2 - curr_idle
            cpu_pct = round(max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100))) if d_total > 0 else 0
            net_bytes_sec = max(0, curr_net2 - curr_net) / max(0.01, dt)
            if curr_gpu_rc6_2 >= 0 and curr_gpu_rc6 >= 0:
                d_rc6 = curr_gpu_rc6_2 - curr_gpu_rc6
                dt_ms = dt * 1000
                if dt_ms > 0 and d_rc6 >= 0:
                    gpu_pct = max(0, min(100, round(100 - (d_rc6 / dt_ms) * 100)))
    else:
        # First sample fallback
        time.sleep(0.05)
        now2, curr_idle2, curr_total2, curr_net2, curr_gpu_rc6_2 = get_current_counters()
        dt = now2 - now
        d_total = curr_total2 - curr_total
        d_idle = curr_idle2 - curr_idle
        cpu_pct = round(max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100))) if d_total > 0 else 0
        net_bytes_sec = max(0, curr_net2 - curr_net) / max(0.01, dt)
        if curr_gpu_rc6_2 >= 0 and curr_gpu_rc6 >= 0:
            d_rc6 = curr_gpu_rc6_2 - curr_gpu_rc6
            dt_ms = dt * 1000
            if dt_ms > 0 and d_rc6 >= 0:
                gpu_pct = max(0, min(100, round(100 - (d_rc6 / dt_ms) * 100)))

    # Save state
    try:
        with open(STATE_FILE, "w") as f:
            json.dump({
                "time": now,
                "idle": curr_idle,
                "total": curr_total,
                "net": curr_net,
                "gpu_rc6": curr_gpu_rc6
            }, f)
    except:
        pass

    if net_bytes_sec >= 1024 * 1024:
        net_str = f"{net_bytes_sec / (1024 * 1024):.1f} MB/s"
    elif net_bytes_sec >= 1024:
        net_str = f"{net_bytes_sec / 1024:.0f} KB/s"
    else:
        net_str = f"{int(net_bytes_sec)} B/s"

    # RAM
    mem = {}
    try:
        with open('/proc/meminfo') as f:
            for line in f:
                parts = line.split(':')
                if len(parts) == 2:
                    mem[parts[0].strip()] = int(parts[1].split()[0])
        total_kb = mem.get('MemTotal', 1)
        avail_kb = mem.get('MemAvailable', mem.get('MemFree', 0))
        used_kb = max(0, total_kb - avail_kb)
        ram_pct = round((used_kb / total_kb) * 100)
        ram_used_gb = round(used_kb / (1024 * 1024), 1)
        ram_total_gb = round(total_kb / (1024 * 1024), 1)
    except:
        ram_pct, ram_used_gb, ram_total_gb = 0, 0, 0

    # Disk
    try:
        du = shutil.disk_usage('/')
        disk_pct = round((du.used / du.total) * 100)
        disk_used_gb = round(du.used / (1024**3), 1)
        disk_free_gb = round(du.free / (1024**3), 1)
        disk_total_gb = round(du.total / (1024**3), 1)
    except:
        disk_pct, disk_used_gb, disk_free_gb, disk_total_gb = 0, 0, 0, 0

    # Temperature
    temp_c = 0
    try:
        temps = []
        for p in glob.glob('/sys/class/thermal/thermal_zone*/temp'):
            try:
                with open(p) as f:
                    v = int(f.read().strip())
                    if v > 1000: v /= 1000
                    if 20 <= v <= 115:
                        temps.append(v)
            except:
                pass
        if temps:
            temp_c = round(sum(temps) / len(temps))
        else:
            for p in glob.glob('/sys/class/hwmon/hwmon*/temp*_input'):
                try:
                    with open(p) as f:
                        v = int(f.read().strip()) / 1000
                        if 20 <= v <= 115:
                            temps.append(v)
                except:
                    pass
            if temps:
                temp_c = round(sum(temps) / len(temps))
    except:
        pass

    return {
        "cpu": cpu_pct,
        "gpu": gpu_pct,
        "ram": ram_pct,
        "ram_used": ram_used_gb,
        "ram_total": ram_total_gb,
        "disk": disk_pct,
        "disk_used": disk_used_gb,
        "disk_free": disk_free_gb,
        "disk_total": disk_total_gb,
        "temp": temp_c,
        "net": net_str
    }

if __name__ == '__main__':
    print(json.dumps(get_sysmon()))
