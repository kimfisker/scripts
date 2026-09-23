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

# 3. Spoof OS-Release Prompt
read -p "Do you want to spoof /etc/os-release to look like Ubuntu? (y/n): " SPOOF_OS
case "$SPOOF_OS" in
    [Yy]* ) 
        SHOULD_SPOOF=true
        ;;
    * ) 
        SHOULD_SPOOF=false
        echo "Skipping /etc/os-release modification."
        ;;
esac

# 4. Clone Repository
TEMP_DIR=$(mktemp -d)
echo "Cloning repository into temporary directory $TEMP_DIR..."
git clone https://github.com/paasimar/intune-fedora43.git "$TEMP_DIR/intune-fedora43"
cd "$TEMP_DIR/intune-fedora43"

# 5. Install Local RPMs & Copy Repos
dnf install -y ./javascriptcoregtk4.0-2.47.2-3.fc42.x86_64.rpm ./webkit2gtk4.0-2.47.2-3.fc42.x86_64.rpm
cp *.repo /etc/yum.repos.d/

# 6. Install Dependencies & Intune
dnf install -y microsoft-edge-stable temurin-11-jdk openssl-libs.i686 gtk3-devel
dnf --setopt=install_weak_deps=false install -y intune-portal

# 7. Modify /etc/os-release if requested
if [ "$SHOULD_SPOOF" = true ]; then
    echo "Modifying /etc/os-release to spoof Ubuntu..."
    sed -i 's/^ID=fedora/ID=ubuntu/' /etc/os-release
    sed -i 's/^VERSION_ID=44/VERSION_ID=26.04/' /etc/os-release
fi

# 8. Force-reinstall WebKit RPMs
rpm -ivh --nodeps --force javascriptcoregtk4.0-*.rpm webkit2gtk4.0-*.rpm

# 9. Cleanup Processes, Cache, & Repositories
pkill -f "/opt/microsoft/intune" || true
rm -rf "$USER_HOME/.cache/microsoft-com.microsoft.intuneportal/"
rm -rf "$USER_HOME/.cache/intune-portal" "$USER_HOME/.config/intune-portal"
cd "$USER_HOME"
rm -rf "$TEMP_DIR"

if [ -f /opt/microsoft/intune/bin/intune-portal ]; then
    echo "Intune installation completed successfully."
else
    echo "Intune binary missing; installation failed."
    exit 1
fi

# 10. Launch Intune Portal in the logged-in user context
echo "Starting Intune Portal..."
sudo -u "$REAL_USER" env \
  LIBGL_ALWAYS_SOFTWARE=1 \
  WEBKIT_DISABLE_COMPOSITING_MODE=1 \
  WEBKIT_FORCE_SANDBOX=0 \
  LD_PRELOAD="/usr/lib64/libssl.so.3:/usr/lib64/libcrypto.so.3:/usr/lib/libcrypto-332.so:/usr/lib/libssl-332.so" \
  DISPLAY="${DISPLAY:-:0}" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
  /opt/microsoft/intune/bin/intune-portal
