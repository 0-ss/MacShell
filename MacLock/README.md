# MacLock Hyprland IPC integration

MacLock has a dedicated Quickshell IPC endpoint, `lockscreen.lock`. The helper `lock-via-ipc.sh` makes the keybind self-starting: it starts an IPC-capable MacLock instance if needed, waits for it to become ready, then requests the lock. Each lock process exits after unlock; the helper starts a fresh one for the next lock because a Wayland session-lock object should not be reused.

## Install

Copy this `MacLock` directory to `~/.config/quickshell/MacLock/` so `shell.qml` is at `~/.config/quickshell/MacLock/shell.qml`.

In your Lua-driven Hyprland config, add:

```lua
hl.bind("SUPER + L", hl.dsp.exec_cmd("sh ~/.config/quickshell/MacLock/lock-via-ipc.sh"))
```

This uses the `hl.bind` / `hl.dsp.exec_cmd` style. Change `SUPER + L` if that key is already used, and adjust the helper path if you installed MacLock elsewhere.

## Direct IPC

If an IPC-capable MacLock instance is currently running, the direct IPC command is:

```sh
qs -c MacLock ipc call lockscreen lock
```

The helper launches the IPC-capable process with `MACLOCK_DAEMON=1`. Existing setups that run `qs -c MacLock` directly (for example from `maclock.sh`/hypridle) keep the original one-shot behavior: the session locks immediately and MacLock exits after unlock.

Preview mode is unchanged: `MACLOCK_PREVIEW=1 qs -c MacLock` opens the visual preview and does not request a real lock.
