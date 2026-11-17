# MacGreeter: the MacShell login screen

MacGreeter shows the same screen as MacLock (`LockScreen.qml` is copied from your MacLock install, not duplicated in the
repository) and logs in through [greetd](https://sr.ht/~kennylevinsen/greetd/). Arch Linux + Hyprland.

```
boot -> greetd -> macshell-greeter -> a tiny Hyprland -> qs -p /usr/local/share/macshell-greeter -> your Hyprland session
```

## Set it up

Install MacShell first (it brings MacLock and this folder), then:

```sh
macshell-install --login-screen          # asks for your sudo password
```

or switch on **Login screen** in the graphical installer (`macshell-installer`). It

- installs `greetd` (pacman) and writes `/etc/greetd/config.toml` (the old file is kept as `config.toml.macshell-backup`),
- copies the login screen to `/usr/local/share/macshell-greeter` and the launcher to `/usr/local/bin/macshell-greeter`,
- remembers the display manager that was on (SDDM, GDM, ...) and replaces it with greetd,
- copies your name, picture, wallpaper, clock look, language and keyboard layout to `/var/lib/macshell-greeter/users/<you>/`.

Nothing changes until you reboot. The login screen offers every account that has an ID of 1000 or more, a session picker
(from `/usr/share/wayland-sessions`) and Sleep / Restart / Shut Down.

## Keep it current

`macshell-greeter-sync` (no sudo needed) refreshes the wallpaper, picture and settings the login screen shows. MacShell runs
it a few seconds after every login, and you can run it by hand. After updating MacShell run
`macshell-install --login-screen` again so the login screen uses the new MacLock files.

## Try it without logging out

```sh
MACGREETER_PREVIEW=1 qs -p /usr/local/share/macshell-greeter      # any password "works"; Ctrl+Shift+Q closes it
```

## If something goes wrong

- Press Ctrl+Alt+F2, log in, and run `macshell-install --remove-login-screen`: it puts the old display manager back.
- Logs: `/var/lib/macshell-greeter/state/greeter.log` and `hyprland.log`.
- The session you log in to writes its output to `~/.cache/macshell-session.log` (read it from a TTY if the screen drops back to the login).
- greetd runs the session command through `sh -c` itself, so `Greetd.launch` must get a plain command line, never `sh -lc ...`.
- Graphics problems: put `export QSG_RHI_BACKEND=opengl` (or `QT_QUICK_BACKEND=software`) in `/var/lib/macshell-greeter/env`.
- Quickshell must be built with its greetd module (the default Arch package is).

## Remove it

```sh
macshell-install --remove-login-screen
```

Disables greetd, turns the previous display manager back on, restores `config.toml` and deletes the files above.
