#!/bin/bash

# Custom Arch Linux install script, meant for installing as a guest in VirtualBox

echo "Enter disk to partition (e.g. /dev/sdX):"
read pdisk
pdisk1=$pdisk"1"
pdisk2=$pdisk"2"
(echo "g"; echo "n"; echo "1"; echo; echo "+512M"; echo "n"; echo "2"; echo; echo; echo "t"; echo "1"; echo "uefi"; echo "t"; echo "2"; echo "23"; echo "w") | fdisk $pdisk

# Format partitions
mkfs.ext4 $pdisk2
mkfs.fat -F 32 $pdisk1

# Mount partitions
mount $pdisk2 /mnt
mount --mkdir $pdisk1 /mnt/boot

# Make swapfile
mkswap -U clear --size 4G --file /mnt/swapfile
swapon /mnt/swapfile

# Install kernel and necessary packages
pacstrap -K /mnt base linux base-devel dosfstools e2fsprogs networkmanager vim man-db man-pages virtualbox-guest-utils git
echo

# Make fstab
genfstab -U /mnt >> /mnt/etc/fstab
uuid=$(cat /mnt/etc/fstab | grep ext4 | cut -f1)

# Prompt for timezone and make symlink to /etc/localtime
echo "Enter timezone from /usr/share/zoneinfo/:"
read -r timezone
ln -sf /mnt/usr/share/zoneinfo/$timezone /etc/localtime

# Update system clock
arch-chroot /mnt hwclock --systohc

# Generate locale and set hostname
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
echo 'arch-vm' > /mnt/etc/hostname

# Enable necessary services
arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable vboxservice.service

# create new password for root
passwd -R /mnt root

arch-chroot /mnt bootctl install

echo -e 'title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=$uuid rw' > /mnt/boot/loader/entries/arch.conf
echo -e 'title Arch Linux (fallback initramfs)\nlinux /vmlinuz-linux\ninitrd /initramfs-linux-fallback.img\noptions root=$uuid rw' > /mnt/boot/loader/entries/arch-fallback.conf

sed -i '1i default arch.conf' /mnt/boot/loader/loader.conf
