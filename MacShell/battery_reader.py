#!/usr/bin/env python3
import glob, json, subprocess, os, sys

def get_battery_info():
    devices = []
    seen_ids = set()

    # 1. Main laptop battery from /sys/class/power_supply
    for bat in sorted(glob.glob('/sys/class/power_supply/BAT*')):
        try:
            name = os.path.basename(bat)
            cap = int(open(f'{bat}/capacity').read().strip())
            status = open(f'{bat}/status').read().strip().lower()
            model = open(f'{bat}/model_name').read().strip() if os.path.exists(f'{bat}/model_name') else 'Battery'
            charging = (status == 'charging')
            
            # Estimate time remaining if available
            time_rem = ""
            if os.path.exists(f'{bat}/energy_now') and os.path.exists(f'{bat}/power_now'):
                try:
                    en = float(open(f'{bat}/energy_now').read().strip())
                    p = float(open(f'{bat}/power_now').read().strip())
                    if p > 0:
                        hrs = en / p if not charging else (float(open(f'{bat}/energy_full').read().strip()) - en) / p
                        if 0 < hrs < 24:
                            time_rem = f"{int(hrs)}h {int((hrs % 1) * 60)}m"
                except:
                    pass

            devices.append({
                'id': name,
                'name': 'MacBook' if any(x in model.lower() for x in ['mac', 'apple']) else 'Internal Battery',
                'type': 'laptop',
                'percentage': cap,
                'charging': charging,
                'status': status,
                'time': time_rem
            })
            seen_ids.add(name.lower())
        except Exception:
            pass

    # 2. UPower peripherals (mouse, keyboard, headset)
    try:
        out = subprocess.run(['upower', '-d'], capture_output=True, text=True, timeout=2).stdout
        curr = {}
        for line in out.splitlines():
            line = line.strip()
            if line.startswith('Device:'):
                dev_path = line.split()[-1]
                if curr and 'percentage' in curr and curr.get('type') not in ['laptop', 'line_power']:
                    if curr.get('id') not in seen_ids:
                        devices.append(curr)
                        seen_ids.add(curr.get('id'))
                curr = {'id': dev_path, 'type': 'peripheral', 'name': 'Device', 'charging': False}
                low = dev_path.lower()
                if 'mouse' in low: curr['type'] = 'mouse'; curr['name'] = 'Magic Mouse'
                elif 'keyboard' in low: curr['type'] = 'keyboard'; curr['name'] = 'Magic Keyboard'
                elif 'head' in low or 'audio' in low or 'ear' in low: curr['type'] = 'headphones'; curr['name'] = 'AirPods'
                elif 'bat' in low or 'display' in low: curr['type'] = 'laptop'
            elif line.startswith('model:'):
                m = line.split(':', 1)[1].strip()
                if m and m != 'Unknown': curr['name'] = m
            elif line.startswith('percentage:'):
                val = line.split(':', 1)[1].strip().replace('%', '')
                try: curr['percentage'] = int(val)
                except: pass
            elif line.startswith('state:'):
                curr['charging'] = ('charging' in line.lower())
        if curr and 'percentage' in curr and curr.get('type') not in ['laptop', 'line_power']:
            if curr.get('id') not in seen_ids:
                devices.append(curr)
                seen_ids.add(curr.get('id'))
    except Exception:
        pass

    # 3. Connected bluetooth devices
    try:
        conn = subprocess.run(['bluetoothctl', 'devices', 'Connected'], capture_output=True, text=True, timeout=2).stdout
        for line in conn.splitlines():
            parts = line.split()
            if len(parts) >= 3:
                mac = parts[1]
                bname = ' '.join(parts[2:])
                info = subprocess.run(['bluetoothctl', 'info', mac], capture_output=True, text=True, timeout=2).stdout
                for iline in info.splitlines():
                    if 'Battery Percentage:' in iline:
                        try:
                            val = int(iline.split('(')[1].split(')')[0])
                            low_info = info.lower()
                            dtype = 'headphones' if any(k in low_info for k in ['head', 'audio', 'tws', 'airpod']) else ('mouse' if 'mouse' in low_info else 'peripheral')
                            if not any(d.get('name') == bname for d in devices):
                                devices.append({
                                    'id': mac,
                                    'name': bname,
                                    'type': dtype,
                                    'percentage': val,
                                    'charging': False,
                                    'status': 'connected'
                                })
                        except:
                            pass
    except Exception:
        pass

    # Fallback if no battery found at all (e.g. desktop PC plugged into AC)
    if not devices:
        devices.append({
            'id': 'AC',
            'name': 'Power Adapter',
            'type': 'laptop',
            'percentage': 100,
            'charging': True,
            'status': 'connected'
        })

    return devices

if __name__ == '__main__':
    print(json.dumps(get_battery_info()))

