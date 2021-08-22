#!/bin/bash

# skip bootstrapping if the raid has already been created
[ -b /dev/md0 ] && exit 0

# install tools
mkdir -p ~root/.ssh
cp ~vagrant/.ssh/auth* ~root/.ssh
yum install -y mdadm smartmontools hdparm gdisk

# prepare media and create RAID6 array
mdadm --zero-superblock --force /dev/sd{b,c,d,e,f}
mdadm --create --verbose /dev/md0 -l 6 -n 5 /dev/sd{b,c,d,e,f}
echo "DEVICE partitions" > /etc/mdadm.conf
mdadm --detail --scan --verbose | grep "ARRAY" >> /etc/mdadm.conf

# split the array device into 5 equal partitions, format & mount them 
parted -s /dev/md0 mklabel gpt
for i in $(seq 1 5); do
    parted /dev/md0 mkpart primary ext4 $((i * 20 - 20))% $((i * 20))%
    mkfs -t ext4 /dev/md0p$i
    mkdir -p /raid/part$i
    mount /dev/md0p$i /raid/part$i
    echo "$(blkid /dev/md0p$i | awk '{print $2}') /raid/part$i ext4 defaults 0 0" >> /etc/fstab
done
