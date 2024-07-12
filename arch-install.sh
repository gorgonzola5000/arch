#!/usr/bin/bash

die() { echo"$*" >&2; exit2; }
needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }

while getopts d:-: OPT; do
  if [ "$OPT" = "-" ]; then
    OPT="${OPTARG%%=*}"
    OPTARG="${OPTARG#"$OPT"}"
    OPTARG="${OPTARG#=}"
  fi
  case "$OPT" in
    d | disk )	disk="$OPTARG" ;;
    nowipe )	nowipe=true ;;
    \? )	exit 2 ;;
    * )		die "Illegal option --$OPT" ;;
  esac
done
shift $((OPTIND-1))

if [[ "$nowipe" = false ]]; then
  cryptsetup open --type plain -d /dev/urandom --cipher aes-xts-plain64 --key-size 256 --hash sha256 --sector-size 4096 $disk to_be_wiped
  dd if=/dev/zero of=/dev/mapper/to_be_wiped status=progress bs=1M
  cryptsetup close to_be_wiped
fi

if [[ $disk =~ "nvme" ]]; then
  diskPartitionSchema="${disk}p"
else
  diskPartitionSchema="$disk"
fi



#create GPT partition
parted -s $disk mklabel gpt


# create boot partition
# maybe --align=optimal
parted -s $disk mkpart "ESP" fat32 1MiB 1025MiB
parted -s $disk set 1 esp on
# root
parted -s $disk mkpart "ROOT" ext4 1025MiB 100%
parted -s $disk type 2 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709

# make fs for EFI partition and LUKS
mkfs.fat -F32 "${diskPartitionSchema}1"
mkfs.ext4 "${diskPartitionSchema}2"

# encrypt root
modprobe dm-crypt
modprobe dm-mod

cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --hash sha256 --iter-time 3000 --key-size 256 --pbkdf argon2id --use-urandom --verify-passphrase "${diskPartitionSchema}2"

cryptsetup open "${diskPartitionSchema}2" archlinux
mkfs.btrfs -L root /dev/mapper/archlinux
# cryptsetup close root

mount -t btrfs /dev/mapper/archlinux /mnt
cd /mnt
btrfs subvolume create root
btrfs subvolume create home
btrfs subvolume create snapshots

cd /
umount -R /mnt
mount -t btrfs -o subvol=root /dev/mapper/archlinux /mnt
mkdir /mnt/home
mount -t btrfs -o subvol=home /dev/mapper/archlinux /mnt/home
mkdir /mnt/snapshots
mount -t btrfs -o subvol=snapshots /dev/mapper/archlinux /mnt/snapshots
mkdir /mnt/boot
mount "${diskPartitionSchema}1" /mnt/boot

cd /mnt
dd if=/dev/zero of=swap bs=1M count=4196
mkswap swap
chmod 0600 swap

pacstrap -i /mnt base base-devel efibootmgr grub networkmanager nano linux linux-firmware

genfstab -U /mnt > /mnt/etc/fstab
arch-chroot /mnt

ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
hwclock --systohc

sed -i  '/^# *en_US.ETF-8 UTF-8/s/^# *//'' /etc/locale.gen
locale-gen
localectl set-locale LANG=en_US.UTF-8
localectl set-locale LC_TIME=en_DK.UTF-8
localectl set-keymap --no-convert pl
hostnamectl hostname arch-T480s

#grub change
touch /etc/default/grub
sed -i '/^GRUB_CMDLINE_LINUX=/c/GRUB_CMDLINE_LINUX=\"cryptdevice=${diskPartitionSchema}2:archlinux\"/' /etc/default/grub
#mkinitcpio
sed -i '/^HOOKS=/c\HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)' /etc/mkinitcpio.conf
mkinitcpio -P

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
exit
reboot

# add user, change shit and stuff
