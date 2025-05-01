#!/bin/bash
while true; do
CHOICE=$(dialog --menu "Disk Management" 15 50 5 \
1 "Show Disk Usage" \
2 "Show LVM Status" \
3 "Create LVM Volume" \
4 "Extend LVM Volume" \
5 "Exit" 3>&1 1>&2 2>&3)
case $CHOICE in
1) dialog --msgbox "$(df -h)" 20 60;;
2) dialog --msgbox "$(vgdisplay && pvdisplay && lvdisplay)" 20 80;;
3)
VG=$(dialog --inputbox "Volume Group Name:" 8 40 3>&1 1>&2 2>&3)
LV=$(dialog --inputbox "Logical Volume Name:" 8 40 3>&1 1>&2 2>&3)
SIZE=$(dialog --inputbox "Size (e.g., 10G):" 8 40 3>&1 1>&2 2>&3)
DEV=$(dialog --inputbox "Device (e.g., /dev/sdb):" 8 40 3>&1 1>&2 2>&3)
pvcreate $DEV && vgcreate $VG $DEV && lvcreate -L $SIZE -n $LV $VG
;;
4)
LV=$(dialog --inputbox "Logical Volume Path:" 8 40 3>&1 1>&2 2>&3)
SIZE=$(dialog --inputbox "Size to add (e.g., +5G):" 8 40 3>&1 1>&2 2>&3)
lvextend -L $SIZE $LV && resize2fs $LV
;;
5) exit;;
esac
done
