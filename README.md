# predator-mode

A power profile manager for the **Acer Predator Helios Neo 16** on Linux. Exposes all five ACPI platform profiles through a simple CLI, with automatic profile setting on login via a systemd user service.

---

## Background

Linux desktop environments (KDE, GNOME) use `power-profiles-daemon`, which hardcodes only three profiles:

| DE Label | → `platform_profile` |
|---|---|
| Power Saver | `low-power` |
| Balanced | `balanced` |
| Performance | `performance` (turbo, uncapped fans) |

The Predator Helios Neo 16 exposes **five** profiles at the kernel level:

```
low-power  quiet  balanced  balanced-performance  performance
```

`balanced-performance` (moderate fan curve, power unlocked but capped) is inaccessible from any standard DE widget, and clicking "Performance" in KDE activates full turbo mode. This tool solves both problems.

---

## Features

- Switch between all 5 ACPI platform profiles from the terminal
- Cycle through profiles in sequence — bind to a keyboard shortcut
- Desktop notifications on profile switch via `notify-send` (if installed)
- Persistent default profile — applied automatically on login via a systemd user service
- Config validation with safe fallback on invalid values
- Self-update from GitHub with a single flag

---

## Requirements

- Linux kernel with ACPI `platform_profile` support (5.9+)
- `systemd` (user session)
- `sudo`
- `bash`
- `curl` (for the installer and `--update`)

Optional:
- `libnotify` / `notify-send` — desktop notifications on profile switch

Tested on:
- **Fedora 44 / 45, KDE Plasma**
- **CachyOS (Arch-based), KDE Plasma**

---

## Installation

### Option A — Installer script (recommended)

```bash
curl -O https://raw.githubusercontent.com/wizsaint/predator-mode/main/install-predator-mode.sh
chmod +x install-predator-mode.sh
./install-predator-mode.sh
```

The installer will:
1. Verify your system exposes the ACPI `platform_profile` interface
2. Download and install `predator-mode` to `~/.local/bin/`
3. Add a scoped sudoers rule for passwordless profile switching
4. Install and enable a systemd user service that applies your default profile after every login

Other installer flags:

```bash
./install-predator-mode.sh --uninstall   # remove everything
./install-predator-mode.sh --version     # print installer version
./install-predator-mode.sh --help        # show usage
```

The uninstaller prompts whether to also remove your saved config (`~/.config/predator-mode/`).

---

### Option B — Manual installation

#### Step 1 — Verify your system

```bash
cat /sys/firmware/acpi/platform_profile_choices
```

You should see the 5 profiles. If the file doesn't exist, your kernel doesn't support this interface.

#### Step 2 — Install the script

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/wizsaint/predator-mode/main/predator-mode \
  -o ~/.local/bin/predator-mode
chmod +x ~/.local/bin/predator-mode
```

Make sure `~/.local/bin` is in your PATH:

**bash / zsh:**
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
```

**fish:**
```fish
fish_add_path ~/.local/bin
```

#### Step 3 — Sudoers rule

```bash
sudo visudo -f /etc/sudoers.d/platform_profile
```

Add this line, replacing `yourusername` with your actual username:

```
yourusername ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile
```

> This rule is narrowly scoped — it only permits `tee` writing to that exact sysfs file. The kernel further restricts writes to the predefined profile names only.

#### Step 4 — Systemd user service

```bash
mkdir -p ~/.config/systemd/user
```

Create `~/.config/systemd/user/predator-profile.service`:

```ini
[Unit]
Description=Set Predator power profile after login
After=graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/home/yourusername/.local/bin/predator-mode
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
```

Enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable --now predator-profile.service
```

---

## Usage

### Profile switching

```bash
predator-mode                  # apply your saved default profile
predator-mode quiet            # switch to a specific profile
predator-mode -c               # cycle to the next profile in sequence
predator-mode -l               # list all profiles (shows active and default)
predator-mode -s               # show current and default profile
predator-mode -d balanced      # save a new default profile
predator-mode -d               # print current default without changing it
predator-mode -h               # show help
```

### Service management

```bash
predator-mode --enable         # enable and start the login service
predator-mode --disable        # disable and stop the login service
predator-mode --service        # show full service status
```

### Updates

```bash
predator-mode --update         # download and install the latest version from GitHub
```

Backs up the current version to `predator-mode.bak` before replacing it.

---

## Profile reference

| Profile | Behaviour |
|---|---|
| `low-power` | Maximum battery saving, lowest performance |
| `quiet` | Minimal fan noise, reduced power |
| `balanced` | Default OS balance (set by KDE on boot) |
| `balanced-performance` | Performance unlocked, fan curve moderate |
| `performance` | Turbo mode, fan fully uncapped |

---

## Keyboard shortcut (cycle profiles)

The `-c` flag cycles profiles in sequence, making it ideal for a keyboard shortcut.

**KDE:** System Settings → Shortcuts → Custom Shortcuts → New → Global Shortcut → Command/URL

Set the command to:

```
/home/yourusername/.local/bin/predator-mode -c
```

Each press cycles to the next profile and sends a desktop notification showing the new profile name (requires `libnotify`).

---

## Desktop notifications

`predator-mode` sends a desktop notification via `notify-send` on every profile switch. Notifications are silently skipped if `notify-send` is not installed.

**Fedora:**
```bash
sudo dnf install libnotify
```

**CachyOS / Arch:**
```bash
sudo pacman -S libnotify
```

---

## Changing the default profile

```bash
predator-mode -d quiet
```

Saves `quiet` to `~/.config/predator-mode/config`. The systemd service reads this on every login. If the saved value is ever invalid, the script warns and falls back to `balanced-performance`.

---

## How it works

The Linux kernel exposes a sysfs file at `/sys/firmware/acpi/platform_profile`. Writing a valid profile name to it switches the hardware immediately:

```bash
echo "balanced-performance" | sudo tee /sys/firmware/acpi/platform_profile
```

`predator-mode` wraps this with validation, a config-based default, and a systemd user service that fires after login — after `power-profiles-daemon` has initialized — so the profile isn't overwritten by the DE.

The sudoers rule allows the script to write to that specific sysfs file without a password prompt, which is required for the systemd user service (which runs as your user, not root) to work correctly.

---

## Troubleshooting

**`predator-mode: command not found`**
`~/.local/bin` is not in your PATH. See Step 2 in the manual installation section.

**`Failed to set profile. Check your sudoers rule.`**
The sudoers rule is missing or incorrect. Re-run Step 3.

**Profile resets to `balanced` after login**
The service isn't running. Check with `predator-mode --service` and re-enable with `predator-mode --enable`.

**Service shows `preset: disabled` on Fedora**
Expected — Fedora's systemd preset policy doesn't auto-enable user services. The installer explicitly enables it so this has no effect on functionality. Verify with:
```bash
systemctl --user is-enabled predator-profile.service   # should print: enabled
```

**No desktop notifications**
Install `libnotify`. See the Desktop notifications section above.

**Warning: Saved default is not a valid profile**
Your `~/.config/predator-mode/config` contains an unrecognised profile name. Reset it with:
```bash
predator-mode -d balanced-performance
```

---

## Limitations

- Profiles available depend entirely on what the hardware and firmware expose. Only tested on the Predator Helios Neo 16.
- `power-profiles-daemon` (KDE/GNOME battery widget) will still show "Balanced" even when `balanced-performance` is active — there is no upstream config file to remap this. A [feature request has been filed](https://gitlab.freedesktop.org/upower/power-profiles-daemon).

---

## License

MIT
