#!/bin/bash

# Custom Arch Linux install script, meant for installing as a guest in VMware

echo -n "Enter disk to partition (e.g. /dev/sdX):"
read disk
echo -n "Enter boot partition size in MiB (e.g. 512, 1024):"
read bootsize
echo -n "Enter size for the swapfile in GiB (e.g. 2, 4):"
read swapsize
echo -n "Enter timezone from /usr/share/zoneinfo/ (e.g. Canada/Eastern, UTC):"
read timezone
echo -n "Enter hostname:"
read hostname
echo -n "Enter any additional packages to install, separated by spaces (Leave blank for none):"
read packages

# Create partition table, an EFI boot partition of specified size and a Linux filesystem which takes up the rest of the disk
sfdisk ${disk} <<- EOF
    label: gpt
    size=${bootsize}M, type=U
    type=L
EOF

# Format partitions
mkfs.ext4 ${disk}2
mkfs.fat -F 32 ${disk}1

# Mount partitions
mount ${disk}2 /mnt
mount --mkdir ${disk}1 /mnt/boot

# Make swapfile
mkswap -U clear --size ${swapsize}G --file /mnt/swapfile
swapon /mnt/swapfile

# Install kernel and necessary packages
pacstrap -K /mnt base linux base-devel dosfstools e2fsprogs networkmanager vim man-db man-pages git open-vm-tools ${packages}
echo

# Make fstab
genfstab -U /mnt >> /mnt/etc/fstab
uuid=$(cat /mnt/etc/fstab | grep ext4 | cut -f1)

# Set timezone with symlink to /mnt/etc/localtime
ln -sf /mnt/usr/share/zoneinfo/${timezone} /mnt/etc/localtime

# Update system clock
arch-chroot /mnt hwclock --systohc

# Generate locale and set hostname
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo ${hostname} > /mnt/etc/hostname

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
