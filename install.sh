#!/bin/bash

# Custom Arch Linux install script, meant for installing as a guest in VMware

echo "Enter disk to partition (e.g. /dev/sdX):"
read pdisk
echo "Enter boot partition size in MiB (e.g. 512, 1024):"
read bootsize
fdisk ${pdisk} <<- fdiskcommands
    g
    n
    1

    +${bootsize}M
    n
    2


    t
    1
    uefi
    t
    2
    23
    w
fdiskcommands

# Format partitions
mkfs.ext4 ${pdisk}2
mkfs.fat -F 32 ${pdisk}1

# Mount partitions
mount ${pdisk}2 /mnt
mount --mkdir ${pdisk}1 /mnt/boot

# Make swapfile
echo "Enter size for the swapfile in GiB (e.g. 2, 4):"
read swapsize
mkswap -U clear --size ${swapsize}G --file /mnt/swapfile
swapon /mnt/swapfile

# Ask for additional packages, then install kernel and necessary packages
echo "Enter any additional packages to install, separated by spaces (Leave blank for none):"
read instpacs
pacstrap -K /mnt base linux base-devel dosfstools e2fsprogs networkmanager vim man-db man-pages git open-vm-tools ${instpacs}
echo

# Make fstab
genfstab -U /mnt >> /mnt/etc/fstab
uuid=$(cat /mnt/etc/fstab | grep ext4 | cut -f1)

# Prompt for timezone and make symlink to /mnt/etc/localtime
echo "Enter timezone from /usr/share/zoneinfo/ (e.g. Canada/Eastern, UTC):"
read -r timezone
ln -sf /mnt/usr/share/zoneinfo/$timezone /mnt/etc/localtime

# Update system clock
arch-chroot /mnt hwclock --systohc

# Generate locale and set hostname
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
echo 'arch-vm' > /mnt/etc/hostname

# Enable necessary services
arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable vmtoolsd.service
arch-chroot /mnt systemctl enable vmware-vmblock-fuse.service

# create new password for root
passwd -R /mnt root

arch-chroot /mnt bootctl install

echo -e "title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=${uuid} rw" > /mnt/boot/loader/entries/arch.conf
echo -e "title Arch Linux (fallback initramfs)\nlinux /vmlinuz-linux\ninitrd /initramfs-linux-fallback.img\noptions root=${uuid} rw" > /mnt/boot/loader/entries/arch-fallback.conf

sed -i '1i default arch.conf' /mnt/boot/loader/loader.conf
