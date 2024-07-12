# change this shit

lsblk
echo "which device to encrypt"
read disk


if [[ $disk =~ "nvme" ]]; then
$diskPartitionSchema = "${disk}p"
else
$diskPartitionSchema = $disk
fi

cryptsetup open --type plain -d /dev/urandom --cipher aes-xts-plain64 --key-size 256 --hash sha256 --sector-size 4096 $disk to_be_wiped
dd if=/dev/zero of=/dev/mapper/to_be_wiped status=progress bs=1M
cryptsetup close to_be_wiped

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

cryptsetup open "/dev/${disk}" root
mkfs.btrfs -L root /dev/mapper/root
cryptsetup close root

mount -t btrfs /dev/mapper/root /mnt
cd /mnt
btrfs subvolume create root /mnt
btrfs subvolume create home
btrfs subvolume create snapshots

umount -R /mnt
mount -t btrfs -o subvol=root /dev/mapper/root /mnt
mkdir /mnt/home
mount -t btrfs -o subvol=home /dev/mapper/root /mnt/home
mkdir /mnt/snapshots
mount -t btrfs -o subvol=snapshots /dev/mapper/root /mnt/snapshots
mkdir /mnt/boot
mount "/dev/${diskPartitionSchema}1" /mnt/boot

cd /mnt
dd if=/dev/zero of=swap bs=1M count 4196
mkswap swap

pacstrap -i /mnt base base-devel efibootmgr grub networkmanager nano linux linux-firmware

genfstab -U /mnt > /mnt/etc/fstab
arch-chroot /mnt
