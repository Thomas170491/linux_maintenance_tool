# Linux Maintenance Tool

A Bash-based Linux Mint maintenance utility with both interactive and automated execution modes.

The tool can perform common system maintenance tasks such as package updates, APT cleanup, cache cleanup, journal cleanup, Docker cleanup, disk usage reporting, and largest-file reporting.

It can be run manually through an interactive menu or automatically on a schedule using `systemd`.

## Features

- System package update and upgrade
- APT package cleanup
- User cache cleanup
- Thumbnail cache cleanup
- Journal log cleanup
- Docker cleanup
- Disk usage reporting
- Top 20 largest file reporting
- Interactive menu
- Non-interactive `--auto` mode
- Weekly automation with a `systemd` timer
- Logging to a maintenance log file

## Requirements

This project is designed primarily for Linux Mint and other Debian/Ubuntu-based systems.

Required tools include:

- Bash
- `apt-get`
- `systemd`
- `journalctl`

Docker cleanup is performed only if Docker is installed.

## Repository structure

```text
linux_maintenance_tool/
├── mint_maintenance.sh
├── systemd/
│   ├── maintenance.service
│   └── maintenance.timer
├── .gitignore
└── README.md
```

## Manual usage

Make the script executable:

```bash
chmod +x mint_maintenance.sh
```

Run it:

```bash
./mint_maintenance.sh
```

This launches the interactive menu:

```text
========================================
 Linux Mint Maintenance Utility
========================================

1) Full maintenance
2) Show disk usage
3) System update
4) APT cleanup
5) Clear user cache
6) Clean journal logs
7) Docker cleanup
8) Show largest files
0) Exit
```

Administrative operations request sudo privileges when required.

## Automatic mode

The script also supports a non-interactive mode:

```bash
sudo ./mint_maintenance.sh --auto
```

In automatic mode, confirmation prompts are skipped and the full maintenance routine runs automatically.

The automatic routine performs:

- disk usage reporting
- system package update and upgrade
- APT cleanup
- journal cleanup
- user cache cleanup
- thumbnail cleanup
- Docker cleanup
- final disk usage reporting
- top 20 largest-file reporting

This mode is intended primarily for use with `systemd`.

## Installing the automated version

For security, the script executed by the root systemd service should be stored in a root-owned location rather than directly inside a user-writable project directory.

Copy the script to `/usr/local/sbin`:

```bash
sudo cp mint_maintenance.sh /usr/local/sbin/mint-maintenance
```

Set root ownership:

```bash
sudo chown root:root /usr/local/sbin/mint-maintenance
```

Set executable permissions:

```bash
sudo chmod 755 /usr/local/sbin/mint-maintenance
```

The production script is now available at:

```text
/usr/local/sbin/mint-maintenance
```

## Configure the systemd service

The repository includes:

```text
systemd/maintenance.service
```

Before installing it, edit the service file and replace:

```ini
Environment="TARGET_USER=your-username"
Environment="TARGET_HOME=/home/your-username"
```

with your actual username and home directory.

For example:

```ini
Environment="TARGET_USER=alice"
Environment="TARGET_HOME=/home/alice"
```

The complete service template is:

```ini
[Unit]
Description=Linux Mint weekly maintenance
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment="TARGET_USER=your-username"
Environment="TARGET_HOME=/home/your-username"
ExecStart=/usr/local/sbin/mint-maintenance --auto
NoNewPrivileges=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
RestrictRealtime=true
LockPersonality=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
UMask=0077
```

Install the service:

```bash
sudo cp systemd/maintenance.service /etc/systemd/system/
```

## Configure the systemd timer

The repository also includes:

```text
systemd/maintenance.timer
```

The default configuration runs maintenance every Friday at 19:00:

```ini
[Unit]
Description=Run maintenance every Friday

[Timer]
OnCalendar=Fri 19:00
Persistent=true

[Install]
WantedBy=timers.target
```

Install the timer:

```bash
sudo cp systemd/maintenance.timer /etc/systemd/system/
```

`Persistent=true` means that if the computer is powered off at the scheduled time, systemd can run the missed maintenance job after the machine starts again.

## Enable the weekly timer

Reload systemd after installing or modifying the unit files:

```bash
sudo systemctl daemon-reload
```

Enable and start the timer:

```bash
sudo systemctl enable --now maintenance.timer
```

Check the timer:

```bash
systemctl status maintenance.timer
```

Or list its next execution time:

```bash
systemctl list-timers maintenance.timer
```

## Test the service manually

Before relying on the timer, test the service:

```bash
sudo systemctl start maintenance.service
```

Then inspect its status:

```bash
systemctl status maintenance.service
```

A successful `Type=oneshot` service normally finishes with:

```text
Active: inactive (dead)
```

and:

```text
status=0/SUCCESS
```

This is expected because a oneshot service exits after completing its task.

## View logs

View logs from previous maintenance runs:

```bash
journalctl -u maintenance.service
```

View logs from the current boot:

```bash
journalctl -u maintenance.service -b
```

Follow a maintenance run live:

```bash
journalctl -fu maintenance.service
```

The script also writes maintenance output to:

```text
~/linux_maintenance.log
```

unless another `LOG_FILE` value is configured.

## Configuration

The script supports the following environment variables:

```text
TARGET_USER
TARGET_HOME
LOG_FILE
```

A `.env` file may also be placed next to the script.

The repository ignores `.env` files by default:

```gitignore
.env
```

Do not commit secrets or machine-specific credentials to Git.

## APT automation

The script uses `apt-get` rather than `apt` for automated package operations.

For example:

```bash
apt-get update
apt-get upgrade -y
apt-get autoremove -y
apt-get autoclean -y
apt-get clean
```

`apt-get` is preferred for scripting because its command-line interface is intended to remain stable for automated usage.

## Docker cleanup

If Docker is installed, the full maintenance routine runs:

```bash
docker system prune -f
```

This removes unused Docker resources. Review this behavior before enabling automatic maintenance if you want to retain unused containers, images, networks, or build cache.

## Security notes

- The systemd service runs as root.
- The production script should therefore be root-owned.
- Avoid executing a user-writable script directly as root from systemd.
- Keep `.env` files and logs out of version control.
- Review automatic cleanup behavior before enabling the timer.
- The service uses a conservative systemd hardening profile.
- Hardening is intentionally conservative to preserve reliability for `apt-get`, Docker, journal cleanup, and user-home maintenance.
- More aggressive sandboxing such as `PrivateNetwork=true`, `ProtectSystem=strict`, or broad syscall/capability filtering may break legitimate maintenance tasks and should be tested carefully before enabling.

## License

Add a license file if you plan to distribute or reuse this project publicly.