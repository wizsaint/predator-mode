# predator-mode

Switch between all five ACPI power profiles on the **Acer Predator Helios Neo 16** from Linux, and optionally have your preferred one applied automatically at login.

## Why

KDE and GNOME talk to `power-profiles-daemon`, which only knows three profiles. The Predator exposes five at the kernel level:

```
low-power  quiet  balanced  balanced-performance  performance
```

Clicking "Performance" in the desktop widget selects `performance` (turbo, fans fully uncapped). `balanced-performance` (power unlocked, moderate fan curve) can't be reached from the widget at all. `predator-mode` fills that gap.

## Install and update

```bash
curl -fsSLO https://raw.githubusercontent.com/wizsaint/predator-mode/main/install-predator-mode.sh
bash install-predator-mode.sh
```

The same two commands install, update and repair. The installer compares each component with what's already on your system and only touches what differs:

| Component | Location | What the installer does |
|---|---|---|
| Script | `~/.local/bin/predator-mode` | Installs it, or replaces it if the content changed (old copy kept as `.bak`) |
| Sudoers rule | `/etc/sudoers.d/platform_profile` | Creates or repairs it, syntax-checked before it goes live |
| Login service | `~/.config/systemd/user/predator-profile.service` | Installs or repairs it. Off by default: turn it on with `predator-mode --enable` |

It explains what it finds and what it's doing at every step, and it never changes your current profile, your saved default, or whether the login service is on.

To remove everything: `bash install-predator-mode.sh --uninstall`

Requires Linux 5.12+ (when ACPI platform profiles landed), systemd, sudo, curl. Run it as your normal user, not as root.

## Usage

```bash
predator-mode                  # apply your saved default
predator-mode quiet            # switch to a profile
predator-mode -c               # cycle to the next profile
predator-mode -l               # list profiles (active and default marked)
predator-mode -s               # current profile, default, login service state
predator-mode -d quiet         # save a new default (applied at next login)
predator-mode -d               # show the saved default
predator-mode --enable         # apply your default at every login (opt-in)
predator-mode --disable        # disable it
predator-mode -v               # version
```

| Profile | Behaviour |
|---|---|
| `low-power` | Maximum battery saving |
| `quiet` | Reduced power, minimal fan noise |
| `balanced` | What KDE sets by default |
| `balanced-performance` | Power unlocked, moderate fan curve |
| `performance` | Turbo, fans fully uncapped |

**Keyboard shortcut:** bind `~/.local/bin/predator-mode -c` in System Settings → Shortcuts → Custom Shortcuts. With `libnotify` installed (`notify-send`), switching by name or with `-c` shows a notification; applying the default (what the login service does) is silent.

## Manual install

If you'd rather not run the installer:

```bash
mkdir -p ~/.local/bin ~/.config/systemd/user
curl -fsSL https://raw.githubusercontent.com/wizsaint/predator-mode/main/predator-mode -o ~/.local/bin/predator-mode
chmod +x ~/.local/bin/predator-mode
```

Add the sudoers rule (replace `yourusername`):

```bash
sudo visudo -f /etc/sudoers.d/platform_profile
```
```
yourusername ALL=(root) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile
```

Create `~/.config/systemd/user/predator-profile.service` (`%h` is your home directory):

```ini
[Unit]
Description=Apply the default Predator power profile after login
After=graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=%h/.local/bin/predator-mode
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
```

```bash
systemctl --user daemon-reload
```

The login service is opt-in: run `predator-mode --enable` if you want your default applied at every login.

To update a manual install, repeat the `curl` line.

## How it works

Writing a profile name to `/sys/firmware/acpi/platform_profile` switches the hardware immediately. That file is root-only, so the sudoers rule allows exactly one thing without a password: `tee` writing to that file. The kernel rejects any value it doesn't know.

The service runs after login rather than at boot because the desktop's power management applies its own profile during startup and would overwrite an earlier setting.

## Troubleshooting

- **`predator-mode: command not found`**: `~/.local/bin` isn't on your PATH. bash/zsh: add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` / `~/.zshrc`. fish: `fish_add_path ~/.local/bin`.
- **"could not write to /sys/firmware/acpi/platform_profile"**: the sudoers rule is missing. Re-run the installer.
- **Profile is `balanced` after login**: check `predator-mode -s`. If the login service shows `disabled` or `not installed`, run `predator-mode --enable` or re-run the installer.
- **"saved default … is not available"**: your config names a profile this machine doesn't offer. Fix it with `predator-mode -d balanced-performance`.

## Limitations

Only tested on the Predator Helios Neo 16 (Fedora 44/45 and CachyOS, KDE Plasma). The KDE/GNOME power widget keeps showing "Balanced" while `balanced-performance` is active, because `power-profiles-daemon` has no way to remap its profiles.

## License

MIT, see [LICENSE](LICENSE).
