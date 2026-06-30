#!/bin/bash

set -ouex pipefail

## DNF5 Speedup
sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf

# Fix per RPM che installano dentro /opt su immagini Atomic/bootc
mkdir -p /var/opt

if [ ! -e /opt ]; then
    ln -s /var/opt /opt
elif [ -L /opt ]; then
    opt_target="$(readlink /opt)"

    case "$opt_target" in
        /*)
            mkdir -p "$opt_target"
            ;;
        *)
            mkdir -p "/$opt_target"
            ;;
    esac
fi

cp -avf "/ctx/system_files"/. /

## Install Cosign
LATEST_VERSION=$(curl https://api.github.com/repos/sigstore/cosign/releases/latest | grep tag_name | cut -d : -f2 | tr -d "v\", ")
curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-${LATEST_VERSION}-1.x86_64.rpm"
rpm -ivh cosign-${LATEST_VERSION}-1.x86_64.rpm


## Install Helium Browser
sudo curl --output-dir "/etc/yum.repos.d/" \
  --remote-name "https://copr.fedorainfracloud.org/coprs/imput/helium/repo/fedora-$(rpm -E %fedora)/imput-helium-fedora-$(rpm -E %fedora).repo"
dnf -y install helium-bin

# 1Password repository
rpm --import https://downloads.1password.com/linux/keys/1password.asc

cat > /etc/yum.repos.d/1password.repo << EOF
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

## System apps
dnf -y install libvirt virt-manager qemu-kvm flatpak-builder lxpolkit lxqt-openssh-askpass just power-profiles-daemon cups-pk-helper kf5-kimageformats zsh git curl zoxide fzf nvim micro

# Imposta zsh come shell predefinita per i nuovi utenti creati dopo l'installazione
sed -i 's|^SHELL=.*|SHELL=/usr/bin/zsh|' /etc/default/useradd

# User apps
dnf -y install nautilus gnome-terminal gnome-system-monitor gnome-calculator loupe 1password 1password-cli

# OBS and fully-featured ffmpeg with nonfree components from rpm fusion
dnf -y install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf -y install ffmpeg x264-libs obs-studio obs-studio-plugin-x264 libva-utils --allowerasing

# Nautilus open any terminal extension
curl -Lo /etc/yum.repos.d/nautilus-open-any-terminal.repo \
  https://copr.fedorainfracloud.org/coprs/monkeygold/nautilus-open-any-terminal/repo/fedora-$(rpm -E %fedora)/monkeygold-nautilus-open-any-terminal-fedora-$(rpm -E %fedora).repo
# dnf install -y nautilus-open-any-terminal
# glib-compile-schemas /usr/share/glib-2.0/schemas
# gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal kitty

# Install Niri 
dnf -y install niri bibata-cursor-theme

# Install Dank Linux shell
sudo curl --output-dir "/etc/yum.repos.d/" \
  --remote-name "https://copr.fedorainfracloud.org/coprs/avengemedia/dms/repo/fedora-$(rpm -E %fedora)/avengemedia-dms-fedora-$(rpm -E %fedora).repo"
dnf -y install quickshell dms greetd dms-greeter --allowerasing

# Install greetd login manager with dank configuration (still needs some work)
mkdir -p /etc/greetd/
cat > /etc/greetd/config.toml << EOF
[terminal]
vt = 1
[default_session]
user = "greeter"
command = "dms-greeter --command niri"
EOF
rm -f /etc/systemd/system/display-manager.service
ln -s /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable --force greetd.service

mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -s /usr/lib/systemd/user/dms.service /etc/skel/.config/systemd/user/graphical-session.target.wants/
#mkdir -p /etc/skel/.config/niri/
#cp -rf /ctx/dot_config/niri/config.kdl /etc/skel/.config/niri/

## Copy Skel home to /etc/skel for new users
cp -a /ctx/skel/. /etc/skel/

#### Enable podman
systemctl enable podman.socket

# Remove waybar
dnf -y remove waybar

# this is needed for some glib applications
glib-compile-schemas /usr/share/glib-2.0/schemas/

# Remove Terra repos from final image.
# They come from the base image and break bootc-image-builder anaconda-iso
# when gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-terra43 is used.
rm -f /etc/yum.repos.d/terra*.repo
rm -f /usr/etc/yum.repos.d/terra*.repo

# Optional: remove Terra GPG keys too
rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-terra*

## CLEAN UP
# Clean up dnf cache to reduce image size
dnf5 -y clean all
rm -rf /run/dnf /run/selinux-policy
rm -rf /var/lib/dnf
