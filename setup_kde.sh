#!/usr/bin/env bash
set -e

# 1. Root check
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

# 2. Detect OS using /etc/os-release
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="$ID"
    DISTRO_LIKE="$ID_LIKE"
else
    echo "Cannot detect OS distribution. /etc/os-release missing."
    exit 1
fi

echo "Detected OS: $NAME ($DISTRO_ID)"

# 3. Installation logic based on distribution
case "$DISTRO_ID" in
    ubuntu|debian)
        echo "Installing KDE Plasma on Ubuntu/Debian..."
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt install -y kde-standard sddm
        
        # Set SDDM as default display manager
        echo "/usr/sbin/sddm" > /etc/X11/default-display-manager
        systemctl enable sddm --force
        ;;

    fedora)
        echo "Installing KDE Plasma on Fedora..."
        dnf groupinstall -y "KDE Plasma Workspaces"
        dnf install -y sddm-wayland-plasma || dnf install -y sddm
        
        # Enable SDDM Wayland or standard SDDM
        if systemctl list-unit-files | grep -q sddm-wayland.service; then
            systemctl enable sddm-wayland.service --force
        else
            systemctl enable sddm.service --force
        fi
        ;;

    cachyos|arch)
        echo "Installing KDE Plasma on CachyOS/Arch..."
        pacman -S --needed --noconfirm plasma-meta kde-applications sddm sddm-kcm
        
        # Disable GDM if active and enable SDDM
        systemctl disable gdm || true
        systemctl enable sddm --force
        ;;

    nixos)
        echo "Detected NixOS."
        echo "NixOS manages DEs declarative via /etc/nixos/configuration.nix."
        echo "Adding KDE Plasma & SDDM configuration..."

        CONF_FILE="/etc/nixos/configuration.nix"
        
        if [ -f "$CONF_FILE" ]; then
            # Backup existing configuration
            cp "$CONF_FILE" "$CONF_FILE.bak"
            
            # Check if desktopManager or displayManager are already configured
            if ! grep -q "services.desktopManager.plasma6.enable" "$CONF_FILE"; then
                sed -i '/services.xserver.enable/a \  services.desktopManager.plasma6.enable = true;' "$CONF_FILE" 2>/dev/null || \
                echo "services.desktopManager.plasma6.enable = true;" >> "$CONF_FILE"
            fi

            if ! grep -q "services.displayManager.sddm.enable" "$CONF_FILE"; then
                sed -i '/services.xserver.enable/a \  services.displayManager.sddm.enable = true;' "$CONF_FILE" 2>/dev/null || \
                echo "services.displayManager.sddm.enable = true;" >> "$CONF_FILE"
            fi

            if ! grep -q "services.xserver.enable" "$CONF_FILE"; then
                echo "services.xserver.enable = true;" >> "$CONF_FILE"
            fi

            echo "Rebuilding NixOS system..."
            nixos-rebuild switch
        else
            echo "Error: $CONF_FILE not found."
            exit 1
        fi
        ;;

    *)
        # Fallback check for derivatives (e.g. ID_LIKE)
        if [[ "$DISTRO_LIKE" == *"arch"* ]]; then
            echo "Arch derivative detected. Running Pacman setup..."
            pacman -S --needed --noconfirm plasma-meta kde-applications sddm sddm-kcm
            systemctl enable sddm --force
        elif [[ "$DISTRO_LIKE" == *"debian"* ]] || [[ "$DISTRO_LIKE" == *"ubuntu"* ]]; then
            echo "Debian/Ubuntu derivative detected. Running APT setup..."
            apt update && apt install -y kde-standard sddm
            systemctl enable sddm --force
        else
            echo "Unsupported distribution: $DISTRO_ID"
            exit 1
        fi
        ;;
esac

echo "--------------------------------------------------------"
echo "KDE Plasma installation complete and set as default!"
echo "Rebooting into SDDM..."
echo "--------------------------------------------------------"

# 4. Optional Prompt to Reboot
read -p "Do you want to reboot now? (y/n): " REBOOT_CHOICE
if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
    reboot
fi
