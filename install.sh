#! /usr/bin/env bash


# Pre install stuff
pre_install(){
  source ./defaults.sh
  pacman -S --noconfirm archlinux-keyring
  setfont ter-132n
  sed -i 's/^#ParallelDownloads/ParallelDownloads 7/' /etc/pacman.conf
  pacman -S --noconfirm reflector
  reflector -c India --verbose --sort rate -l 10 --save /etc/pacman.d/mirrorlist
}

# Remove all exsiting partitions
remove_partitions(){
  clear
  echo "Removing all existing partitions"
  echo ".." | sudo sfdisk /dev/$DRIVE
}

# Partiton drives
partition_drives(){
  clear
  echo "Partitioning drives..."
  echo "2048,102400,ef," | sudo sfdisk /dev/$DRIVE
  parted /dev/$DRIVE mklabel gpt
  parted /dev/$DRIVE mkpart primary btrfs 2048s 100%
}

# Format drives
format_drives(){
  clear
  echo "Formatting drives.."
  mkfs.fat -F32 $DRIVE"p1"
  mkfs.btrfs $DRIVE"p2"
}

# Mount drives
mount_drives(){
  clear
  echo "Mounting drives.."
  local boot_partiton="$DRIVE"p1
  local btrfs_partiton="$DRIVE"p2
  mount /dev/$DRIVE /mnt

  btrfs su cr /mnt/@
  btrfs su cr /mnt/@home
  btrfs su cr /mnt/@var
  btrfs su cr /mnt/@.snapshots

  umount /mnt

  mount -o noatime,compress=zstd,space_cache=v2,subvol=@ /dev/$btrfs_partiton /mnt 
  mkdir -p /mnt/{boot,home,.snapshots,var}
  mount -o noatime,compress=zstd,space_cache=v2,subvol=@home /dev/$btrfs_partiton /mnt/home
  mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots /dev/$btrfs_partiton /mnt/.snapshots
  mount -o noatime,compress=zstd,space_cache=v2,subvol=@var_log /dev/$btrfs_partiton /mnt/var

  mount /dev/$boot_partiton /mnt/boot
}

# Base install
install_base(){
  clear
  echo "Installing base packages.."
  pacstrap -K /mnt base base-devel vim btrfs-progs linux-firmware vim amd-ucode
}

# Chroot into installation
arch_chroot(){
  clear
  echo "Chrooting into /mnt.."
  arch-chroot /mnt ./script.sh chroot
}

# Set timezone
set_timezone(){
  clear
 echo "Setting timezones.."
 ln -s "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

# Set locale
set_locale(){
  clear
  echo "Setting up locales.."
  echo "LANG=en_US.UTF-8" >> /etc/locale.conf
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
}

# Set hosts
set_hosts(){
  clear
  echo "Setting up hosts.."
  cat >> /etc/hosts <<EOF
  127.0.0.1	    localhost
  ::1		    localhost
  127.0.0.1 	$HOSTNAME.localdomain	$HOSTNAME
  EOF
}

# Generate fstab
gen_fstab(){
  clear
  echo "Generating fstab..."
  genfstab -U /mnt >> /mnt/etc/fstab
  cat /etc/fstab
}

# Set hostname
set_hostname(){
  echo "Setting hostname"
  echo "$HOSTNAME" >> /etc/hostname
}

# Install packages
install_packages(){
  clear
  echo "Installing necessary packages"
  pacman -S networkmanager \
  network-manager-applet \
  dialog wpa_supplicant \
  mstools \
  dosfstools \
  bluez \
  bluez-utils \
  cups \
  xdg-utils \
  xdg-user-dirs \
  base-devel \
  linux-headers \
  git
}

# Configure mkinitpio.conf
config_mkinitcpio(){
  clear
   echo "Building mkinitcpio"
  sed -i 's/^MODULES=(/MODULES=(btrfs /' /etc/mkinitcpio.conf
  mkinitcpio -p linux
}

# Configure grub
configure_grub(){
  clear
  echo "Configuring grub.."
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
  grub-mkconfig -o /boot/grub/gurb.cfg
}

# Add users
setup_user(){
  clear
  echo "Creating user..."
  useradd -m-G  wheel,video,network,lp "$USERNAME"
  echo "$PASSWORD" | passwd --stdin $USERNAME
  sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
}

# Setup daemons
set_daemons(){
  clear
  echo "Enabling daemons.."
  systemctl enable NetworkManager
  systemctl enable bluetooth
  systemctl enable cups
}

# Hyprland specific setup
hyprland_bootstrap(){
  su $USERNAME
  git clone https://github.com/devadathanmb/dotfiles ~
  ./dotfiles/bootstrap.sh
}

hyprland_afterinstall(){
  clear
  echo "After install setup for hyprland.."
  sudo cp /usr/share/wayland-sessions/hyprland.desktop /usr/share/wayland-sessions/hyprland-wrapped.desktop 
  cat > /etc/udev/rules.d/backlight.rules << EOL
  ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video $sys$devpath/brightness", RUN+="/bin/chmod g+w $sys$devpath/brightness"
  EOL
  
  cat > ~/.config/electron-flags.conf << EOL
  --enable-features=UseOzonePlatform --ozone-platform=wayland
  EOL
}

# Before chroot
before_chroot(){
  pre_install
  remove_partitions
  partition_drives
  format_drives
  mount_drives
  install_base
  arch_chroot
}

# After chroot
after_chroot(){
  gen_fstab
  set_timezone
  set_locale
  set_hostname
  set_hosts
  install_packages
  config_mkinitcpio
  configure_grub
  setup_user
  set_daemons
  # hyprland_bootstrap
  # hyprland_afterinstall
}

if [ "$1" == "chroot" ]
then
  after_chroot
else
  before_chroot
fi
