#!/usr/bin/env bash
set -e

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# 2. Hostname Prompt
read -p "Enter your desired hostname (press Enter to skip): " NEW_HOSTNAME
if [ -n "$NEW_HOSTNAME" ]; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "Hostname updated to $NEW_HOSTNAME"
fi

# 3. Spoof /etc/os-release Prompt
read -p "Do you want to spoof /etc/os-release ID to Ubuntu? (y/n): " SPOOF_OS
case "$SPOOF_OS" in
    [Yy]* ) 
        SHOULD_SPOOF=true
        ;;
    * ) 
        SHOULD_SPOOF=false
        echo "Keeping ID as cachyos (only adding VERSION_ID)."
        ;;
esac

# 4. Install Prerequisites
echo "Installing base-devel and git..."
pacman -S --needed --noconfirm base-devel git

# 5. Helper function to build AUR packages as regular user (makepkg refuses to run as root)
build_aur_package() {
    local pkg_url="$1"
    local pkg_dir="$2"
    local temp_workspace="$3"

    echo "Building $pkg_dir..."
    sudo -u "$REAL_USER" bash -c "
        cd '$temp_workspace'
        git clone '$pkg_url'
        cd '$pkg_dir'
        makepkg -si --noconfirm
    "
}

TEMP_DIR=$(mktemp -d)
chown -R "$REAL_USER":"$REAL_USER" "$TEMP_DIR"

# 6. Build and Install AUR Packages
build_aur_package "https://aur.archlinux.org/microsoft-identity-broker-bin.git" "microsoft-identity-broker-bin" "$TEMP_DIR"
build_aur_package "https://aur.archlinux.org/intune-portal-bin.git" "intune-portal-bin" "$TEMP_DIR"
build_aur_package "https://aur.archlinux.org/microsoft-edge-stable-bin.git" "microsoft-edge-stable-bin" "$TEMP_DIR"

# Cleanup build directory
rm -rf "$TEMP_DIR"

# 7. Modify /etc/os-release
if ! grep -q "^VERSION_ID=" /etc/os-release; then
    echo 'VERSION_ID="26.04"' >> /etc/os-release
else
    sed -i 's/^VERSION_ID=.*/VERSION_ID="26.04"/' /etc/os-release
fi

if [ "$SHOULD_SPOOF" = true ]; then
    echo "Modifying ID to ubuntu..."
    sed -i 's/^ID=.*/ID=ubuntu/' /etc/os-release
fi

# 8. Clear Cache & Kill Processes
pkill -f "/opt/microsoft/intune" || true
rm -rf "$USER_HOME/.cache/microsoft-com.microsoft.intuneportal/"
rm -rf "$USER_HOME/.cache/intune-portal" "$USER_HOME/.config/intune-portal"
rm -rf "$USER_HOME/.config/microsoft-identity-broker" "$USER_HOME/.local/state/microsoft-identity-broker"

if [ -f /opt/microsoft/intune/bin/intune-portal ]; then
    echo "Intune installation completed successfully."
else
    echo "Intune binary missing; installation failed."
    exit 1
fi

# 9. Launch Intune Portal in user context
echo "Starting Intune Portal..."
sudo -u "$REAL_USER" env \
  LD_LIBRARY_PATH="/opt/microsoft/intune/bin/openssl/usr/lib:/usr/lib" \
  DISPLAY="${DISPLAY:-:0}" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
  /opt/microsoft/intune/bin/intune-portal
  
read -p "Press [ENTER] once device enrollment is complete in the GUI to setup background sync..."

# ==============================================================================
# Post-Enrollment: Configure Systemd Daemon & Persistence for CachyOS
# ==============================================================================

echo "=== Starting Microsoft Intune Post-Enrollment Setup ==="

# 1. Enable User Lingering
echo "--> Enabling systemd user session lingering..."
sudo loginctl enable-linger "$USER"

# 2. Configure System Daemon Override (Prevents 10-Min Idle Timeout)
echo "--> Setting up systemd override for intune-daemon.service..."
sudo mkdir -p /etc/systemd/system/intune-daemon.service.d

cat << 'EOF' | sudo tee /etc/systemd/system/intune-daemon.service.d/override.conf > /dev/null
[Service]
Restart=always
RestartSec=5s
EOF

# 3. Reload and Enable System-Level Sockets & Services
echo "--> Reloading systemd and enabling intune-daemon socket..."
sudo systemctl daemon-reload
sudo systemctl enable --now intune-daemon.socket
sudo systemctl enable --now intune-daemon.service

# 4. Configure User-Level Hourly Sync Timer & Service
echo "--> Creating user-level systemd sync service and timer..."
mkdir -p ~/.config/systemd/user

# User Service Unit
cat << 'EOF' > ~/.config/systemd/user/intune-sync.service
[Unit]
Description=Intune Automatic Hourly Sync

[Service]
Type=oneshot
Environment="XDG_RUNTIME_DIR=/run/user/%U"
Environment="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
ExecStart=/opt/microsoft/intune/bin/intune-agent
EOF

# User Timer Unit
cat << 'EOF' > ~/.config/systemd/user/intune-sync.timer
[Unit]
Description=Run Intune Sync Hourly

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 5. Enable and Start User Sync Timer
echo "--> Enabling user sync timer..."
systemctl --user daemon-reload
systemctl --user enable --now intune-sync.timer

echo "=== Setup Complete! ==="
echo "Verifying setup status:"
systemctl --user list-timers intune-sync.timer
