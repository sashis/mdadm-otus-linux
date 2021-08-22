# Работа с mdadm

## 1. Собрать систему с подключенным рейдом и смонтированными разделами (*)

Создание рейда и разделов на нём вынес в `bootstrap.sh`, который автоматически запускается 
на этапе `provisioning` при создании виртуальной машины. Для автоматического монтирования 
новых разделов внёс их в `/etc/fstab`

## 2. Перенести рабочую систему на RAID1 (**)

Для этого задания собрал отдельную ВМ (папка `system_to_raid`) с 1 дополнительным диском того же объема (40GB), что и основной. 
Изначально дисковая система выглядит следующим образом
```
[vagrant@otuslinux ~]$ lsblk
NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
sda      8:0    0  40G  0 disk
`-sda1   8:1    0  40G  0 part /
sdb      8:16   0  40G  0 disk
```
Дальнейшие операции выполняются с привилегиями суперпользователя. Сначала копируем разметку рабочего диска
```
sfdisk -d /dev/sda | sfdisk /dev/sdb
```
Меняем тип раздела `/dev/sdb1` на `Linux raid autodetect (FD)`
```
parted /dev/sdb set 1 raid on
```
Собираем из нового раздела degraded RAID1 на два устройства (один раздел пока пропускаем и добавим позже). 
Тип суперблока по рекомендации mdadm задаем версии 0.90. На образованном RAID-массиве `/dev/md0` создаем файловую систему
```
mdadm --create /dev/md0 --level 1 --raid-devices=2 --metadata=0.90 missing /dev/sdb1
mkfs -t ext4 /dev/md0
```
Монтируем наш RAID и копируем в него рабочую систему
```
mount /dev/md0 /mnt/
rsync -axu --exclude '/mnt' / /mnt/
```
Монтируем служебные ФС в новый корневой раздел и меняем корневой каталог для сборки новой `initramfs`
```
mount --bind /proc /mnt/proc
mount --bind /dev /mnt/dev
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run
chroot /mnt/
```
Меняем в `/etc/fstab` рабочий корневой раздел `/dev/sda1` на аналогичный на `/dev/md0`
```
sed -i "/$(blkid -o value -s UUID /dev/sda1)/ s/.*/$(blkid /dev/md0 | awk '{print $2}') \/ ext4 defaults 0 1/" /etc/fstab
```
Сохраняем информацию о RAID для автоматической сборки
```
echo "DEVICE partitions" > /etc/mdadm.conf
mdadm --detail --scan --verbose | grep "ARRAY" >> /etc/mdadm.conf
```
Генерируем новый образ `initramfs` с информацией о RAID-разделе и модулем `mdraid`
```
mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.bak
dracut --force --mdadmconf --add="mdraid" /boot/initramfs-$(uname -r).img $(uname -r)
```
Добавляем передачу ядру параметра `rd.auto=1` при загрузке для автоматического обнаружения и запуска
RAID-устройств и генерируем новую конфигурацию `GRUB`
```
echo 'GRUB_CMDLINE_LINUX="\$GRUB_CMDLINE_LINUX rd.auto=1"' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
```
Переустанавливаем `GRUB` на оба физических устройства `/dev/sda` и `/dev/sdb`
```
grub2-install /dev/sdb
grub2-install /dev/sda
```
Выполнение ранее копирования через rsync требует перемаркировки скопированной ФС для SELinux
```
touch /.autorelabel
```
Теперь можно выходить из `chroot` и перезагрузиться с RAID'а
```
exit
reboot
```
После перезагрузки останется поменять тип раздела для `/dev/sda1`, добавить его в RAID и дождаться
синхронизации
```
parted /dev/sda set 1 raid on
mdadm --manage /dev/md0 --add /dev/sda1
```
После проделанных оперций блочные устройства выглядят следующим образом
```
[root@otuslinux vagrant]# lsblk
NAME    MAJ:MIN RM SIZE RO TYPE  MOUNTPOINT
sda       8:0    0  40G  0 disk
`-sda1    8:1    0  40G  0 part
  `-md0   9:0    0  40G  0 raid1 /
sdb       8:16   0  40G  0 disk
`-sdb1    8:17   0  40G  0 part
  `-md0   9:0    0  40G  0 raid1 /
```