#!/bin/bash

# Custom Arch Linux install script, meant for installing as a guest in VMware

mkbtrfs() {
    # Create partition table with an ESP of chosen size and a Linux filesystem which takes up the rest of the disk
    sfdisk ${disk} <<- EOF
        label: gpt
        size=${bootsize}, type=U
        type=L
    EOF

    # Create array of partitions
    partitions=($(lsblk --list --paths | awk '$6 = /part/ { print $1 }'))

    # Format partitions
    mkfs.fat -F 32 ${partitions[0]}
    mkfs.btrfs ${partitions[1]}

    # Mount top-level subvolume
    mount ${partitions[1]} /mnt

    # Make subvolumes
    btrfs subvolume create /@ /@home /@snapshots /@var_log /@swap

    # Unmount top-level subvolume
    umount /mnt

    # Mount subvolumes
    mount ${partitions[1]} /mnt --options subvol=/@
    mount --mkdir ${partitions[1]} /mnt/home --options subvol=/@home
    mount --mkdir ${partitions[1]} /mnt/.snapshots --options subvol=/@snapshots
    mount --mkdir ${partitions[1]} /mnt/var/log --options subvol=/@var_log
    mount --mkdir ${partitions[1]} /mnt/.swap --options subvol=/@swap

    # Mount ESP
    mount --mkdir ${partitions[0]} /mnt/boot/efi

    # Make and activate swapfile
    btrfs filesystem mkswapfile --size ${swapsize} --uuid clear /mnt/.swap/swapfile
    swapon /mnt/.swap/swapfile
}

mkext4LVM() {
    # Create partition table with an ESP of chosen size and a Linux filesystem which takes up the rest of the disk
    sfdisk ${disk} <<- EOF
        label: gpt
        size=${bootsize}, type=U
        type=L
    EOF

    # Create array of partitions
    partitions=($(lsblk --list --paths | awk '$6 = /part/ { print $1 }'))

    # Get size of partitions to use for LVM, half for root and a quarter for home
    rootsize=$(lsblk --list --paths | awk '$1 = /${partitions[1]}/ { print $4 / 2 })
    homesize=$(lsblk --list --paths | awk '$1 = /${partitions[1]}/ { print $4 / 4 })

    # Create physical volume
    pvcreate ${partitions[1]}

    # Create volume group
    vgcreate vg1 ${partitions[1]}
    
    # Create logical volumes
    lvcreate --size ${rootsize} --name root vg1
    lvcreate --size ${homesize} --name home vg1

    # Format partitions
    mkfs.fat -F 32 ${partitions[0]}
    mkfs.ext4 /dev/vg1/root
    mkfs.ext4 /dev/vg1/home

    # Mount logical volumes
    mount /dev/vg1/root /mnt
    mount --mkdir /dev/vg1/home /mnt/home

    # Mount ESP
    mount --mkdir ${partitions[0]} /mnt/boot/efi

    # Add lvm2 hook to mkinitcpio
    sed --in-place /^HOOKS/s/block/'block lvm2'/ /mnt/etc/mkinitcpio.conf

    # Make and activate swapfile
    mkdir /mnt/.swap
    mkswap --size ${swapsize} --uuid clear --file /mnt/.swap/swapfile
    swapon /mnt/.swap/swapfile
}

makeuki() {
    # Make root.conf in cmdline.d
    mkdir /mnt/etc/cmdline.d
    echo 'root=UUID=${uuid} rw' > /mnt/cmdline.d/root.conf
    
    # Add subvolume name if filesystem is btrfs
    if [(lsblk --noheadings --output FSTYPE ${partitions[1]}) = btrfs ]; do
        echo 'rootflags=subvol=/@' >> /mnt/cmdline.d/root.conf
    done

    # Edit linux preset in mkinitcpio.d
    sed --in-place /default_uki/s/*/default_uki="/boot/efi/EFI/arch-linux.efi"/ /mnt/etc/mkinitcpio.d/linux.preset
    sed --in-place /default_image/s/^/#/ /mnt/etc/mkinitcpio.d/linux.preset

    # And the fallback
    sed --in-place /fallback_uki/s/*/fallback_uki="/boot/efi/EFI/arch-linux-fallback.efi"/ /mnt/etc/mkinitcpio.d/linux.preset
    sed --in-place /fallback_image/s/^/#/ /mnt/etc/mkinitcpio.d/linux.preset

    # Run mkinitcpio
    mkdir --parents /mnt/boot/efi/EFI/Linux
    mkinitcpio --preset linux

    # Remove leftover initramfs images
    rm /mnt/boot/initramfs-*.img

    # Create boot entry with efibootmgr
    efibootmgr --create --disk ${disk} --part 1 --label "Arch Linux" --loader '\EFI\Linux\arch-linux.efi' --unicode
}

########## OPTIONS ##########

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

# Set root password
read -rp "Would you like to set a root password? [Y/n] " newrootpw
while [[ ${newrootpw} =~ [^yYnN] ]]; do
    echo "Invalid answer, try again"
    read -rp "Would you like to set a root password? [Y/n] " newrootpw
done

if [[ ${newrootpw} =~ [yY] ]] || [ -z ${newrootpw }]; then
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
    fi
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

########## INSTALLATION ##########

# If btrfs chosen use that, otherwise use ext4 with LVM
if [${usebtrfs} = true]; then
    mkbtrfs()
else
    mkext4LVM()
fi

# Install kernel and necessary packages
pacstrap -K /mnt base linux base-devel dosfstools e2fsprogs networkmanager vim man-db man-pages git open-vm-tools ${packages}

# Make fstab
genfstab -U /mnt >> /mnt/etc/fstab
uuid=$(lsblk --noheadings --output UUID ${partitions[1]})

# Set timezone with symlink to /mnt/etc/localtime
ln --symbolic --force /mnt/usr/share/zoneinfo/${timezone} /mnt/etc/localtime

# Update system clock
arch-chroot /mnt hwclock --systohc

# Generate locale and set hostname
sed --in-place 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo ${hostname} > /mnt/etc/hostname

# Enable necessary services
arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable vmtoolsd.service
arch-chroot /mnt systemctl enable vmware-vmblock-fuse.service

# create new password for root
if [ -n ${newrootpw} ]; then
    echo ${rootpw} | arch-chroot /mnt passwd --stdin root
if

# Create new password for non-root user, if option selected
if [ -n ${newuser} ]; then
    echo ${userpw} | arch-chroot /mnt passwd --stdin ${username}
fi

# Create UKI, modify mkinitcpio, and add entry to efibootmgr
makeuki()

echo 'Installation finished'
