#!/bin/bash

# Custom Arch Linux install script, meant for installing as a guest in VMware

read -rp "Enter disk to partition [/dev/sda] " disk
if [ -z ${disk} ]; then
    disk=/dev/sda
fi

read -rp "Enter boot partition size [512M] " bootsize
if [ -z ${bootsize} ]; then
    bootsize=512M
fi

read -rp "Enter size for the swapfile [4G] " swapsize
if [ -z ${swapsize} ]; then
    swapsize=4G
fi

read -rp "Enter timezone from /usr/share/zoneinfo/ [UTC] " timezone
if [ -z ${timezone} ]; then
    timezone=UTC
fi

read -rp "Enter hostname [arch-vm] " hostname
if [ -z ${hostname} ]; then
    hostname=arch-vm
fi

read -rp "Enter any additional packages to install, separated by spaces (Leave blank for none): " packages

# Create a new non-root user
read -rp "Would you like to set a root password? [Y/n] " newrootpw
while [[ ${newrootpw} =~ [^yYnN] ]]; do
    echo "Invalid answer, try again"
    read -rp "Would you like to set a root password? [Y/n] " newrootpw
done

if [[ ${newrootpw} =~ [^nN] ]]; then
    read -srp "New password: " rootpw
    echo
    read -srp "Retype new password: " rootpwck
    echo
    while [ ${rootpw} != ${rootpwck} ]; do
        echo "Passwords do not match, try again"
        read -srp "New password: " rootpw
        echo
        read -srp "Retype new password: " rootpwck
        echo
    done
    echo "Password accepted"
fi


# Create a new non-root user
read -rp "Would you like to create a new non-root user? [y/N] " newuser
while [[ ${newuser} =~ [^yYnN] ]]; do
    echo "Invalid answer, try again"
    read -rp "Would you like to create a new non-root user? [y/N] " newuser
done

if [[ ${newuser} =~ [yY] ]]; then

    # Ask for username, if nothing entered set to "user"
    read -rp "Enter username for non-root user [user] " username
    if [ -z ${username} ]; then
        username=user
    fi
    
    # Ask if a password for the new user is wanted
    read -rp "Set password for ${username}? [y/N] " setuserpw
    while [[ ${setuserpw} =~ [^yYnN] ]]; do
        echo "Invalid answer, try again"
        read -rp "Set password for ${username}? [y/N] " setuserpw
    done

    # Set new password for the user
    if [[ ${setuserpw} =~ [yY] ]]; then
        read -srp "New password: " userpw
        echo
        read -srp "Retype new password: " userpwck
        echo
        while [ ${userpw} != ${userpwck} ]; do
            echo "Passwords do not match, try again"
            read -srp "New password: " userpw
            echo
            read -srp "Retype new password: " userpwck
            echo
        done
        echo "Password accepted"
    fi
    
fi



# Create partition table, an EFI boot partition of specified size and a Linux filesystem which takes up the rest of the disk
sfdisk ${disk} <<- EOF
    label: gpt
    size=${bootsize}, type=U
    type=L
EOF

# Format partitions
mkfs.ext4 ${disk}2
mkfs.fat -F 32 ${disk}1

# Mount partitions
mount ${disk}2 /mnt
mount --mkdir ${disk}1 /mnt/boot

# Make swapfile
mkswap -U clear --size ${swapsize} --file /mnt/swapfile
swapon /mnt/swapfile

# Install kernel and necessary packages
pacstrap -K /mnt base linux base-devel dosfstools e2fsprogs networkmanager vim man-db man-pages git open-vm-tools ${packages}
echo

# Make fstab
genfstab -U /mnt >> /mnt/etc/fstab
uuid=$(blkid -o export ${disk}2 | awk '/^UUID/')

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
if [ -!z ${newrootpw} ]; then
    echo ${rootpw} | arch-chroot /mnt passwd -s root
if

# Create new password for non-root user, if option selected
if [ -!z ${newuser} ]; then
    echo ${userpw} | arch-chroot /mnt passwd -s ${username}
fi

# Set up systemd-bootd
arch-chroot /mnt bootctl install

echo -e "title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=${uuid} rw" > /mnt/boot/loader/entries/arch.conf
echo -e "title Arch Linux (fallback initramfs)\nlinux /vmlinuz-linux\ninitrd /initramfs-linux-fallback.img\noptions root=${uuid} rw" > /mnt/boot/loader/entries/arch-fallback.conf

sed -i '1i default arch.conf' /mnt/boot/loader/loader.conf

echo 'Installation finished'
