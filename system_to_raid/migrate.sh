#!/bin/bash

sudo -s
sfdisk -d /dev/sda | sfdisk /dev/sdb
parted /dev/sdb set 1 raid on
mdadm --create /dev/md0 --level 1 --raid-devices=2 --metadata=0.90 missing /dev/sdb1
mkfs -t ext4 /dev/md0
mount /dev/md0 /mnt/
rsync -axu --exclude '/mnt' / /mnt/
mount --bind /proc /mnt/proc
mount --bind /dev /mnt/dev
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run
chroot /mnt/ << EOF
sed -i "/$(blkid -o value -s UUID /dev/sda1)/ s/.*/$(blkid /dev/md0 | awk '{print $2}') \/ ext4 defaults 0 1/" /etc/fstab
echo "DEVICE partitions" > /etc/mdadm.conf
mdadm --detail --scan --verbose | grep "ARRAY" >> /etc/mdadm.conf
mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.bak
dracut --force --mdadmconf --add="mdraid" /boot/initramfs-$(uname -r).img $(uname -r)
echo 'GRUB_CMDLINE_LINUX="\$GRUB_CMDLINE_LINUX rd.auto=1"' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-install /dev/sdb
grub2-install /dev/sda
touch /.autorelabel
EOF

reboot

parted /dev/sda set 1 raid on
mdadm --manage /dev/md0 --add /dev/sda1
