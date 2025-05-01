#!/bin/bash

# Ensure script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    dialog --msgbox "Please run as root." 7 50
    exit
fi

LOG_FILE="/home/$USER/user_management.log"

while true; do
    CHOICE=$(dialog --clear --title "Linux Management Tool" --menu "Select an option:" 15 50 7 \
    1 "Add a New User" \
    2 "Delete a User" \
    3 "Modify User Information" \
    4 "List Users" \
    5 "Disk Usage Dashboard" \
    6 "LVM Management" \
    7 "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1)
            USERNAME=$(dialog --inputbox "Enter username:" 8 40 3>&1 1>&2 2>&3)
            PASSWORD=$(dialog --insecure --passwordbox "Enter password:" 8 40 3>&1 1>&2 2>&3)
            sudo useradd -m "$USERNAME"
            echo "$USERNAME:$PASSWORD" | sudo chpasswd
            echo "$(date): User $USERNAME added" >> $LOG_FILE
            dialog --msgbox "User $USERNAME created successfully!" 6 40
            ;;
        2)
            USERNAME=$(dialog --inputbox "Enter username to delete:" 8 40 3>&1 1>&2 2>&3)
            dialog --yesno "Are you sure you want to delete $USERNAME?" 7 50
            if [ $? -eq 0 ]; then
                sudo userdel -r "$USERNAME"
                echo "$(date): User $USERNAME deleted" >> $LOG_FILE
                dialog --msgbox "User $USERNAME deleted successfully!" 6 40
            fi
            ;;
        3)
            USERNAME=$(dialog --inputbox "Enter username to modify:" 8 40 3>&1 1>&2 2>&3)
            NEWNAME=$(dialog --inputbox "Enter new username:" 8 40 3>&1 1>&2 2>&3)
            sudo usermod -l "$NEWNAME" "$USERNAME"
            echo "$(date): Username changed from $USERNAME to $NEWNAME" >> $LOG_FILE
            dialog --msgbox "Username changed successfully!" 6 40
            ;;
        4)
            USERS=$(cut -d: -f1 /etc/passwd | sort)
            dialog --msgbox "System Users:\n$USERS" 15 50
            ;;
        5)
            DISK_OPTION=$(dialog --menu "Select disk operation:" 15 50 4 \
            1 "Check Disk Space" \
            2 "Show Largest Directories" \
            3 "Monitor in Real-Time" \
            4 "Exit" 3>&1 1>&2 2>&3)

            case $DISK_OPTION in
                1) dialog --msgbox "$(df -h)" 20 60 ;;
                2) dialog --msgbox "$(du -ah / | sort -rh | head -10)" 20 60 ;;
                3) watch -d -n 5 df -h ;;
                4) exit ;;
            esac
            ;;
        6)
            LVM_OPTION=$(dialog --menu "LVM Management" 15 50 4 \
            1 "Create LVM Volume" \
            2 "Extend LVM Volume" \
            3 "View LVM Details" \
            4 "Exit" 3>&1 1>&2 2>&3)

            case $LVM_OPTION in
                1)
                    VG_NAME=$(dialog --inputbox "Enter Volume Group Name:" 8 40 3>&1 1>&2 2>&3)
                    LV_NAME=$(dialog --inputbox "Enter Logical Volume Name:" 8 40 3>&1 1>&2 2>&3)
                    SIZE=$(dialog --inputbox "Enter size (e.g., 10G):" 8 40 3>&1 1>&2 2>&3)
                    DEVICE=$(dialog --inputbox "Enter device (e.g., /dev/sdb):" 8 40 3>&1 1>&2 2>&3)

                    sudo pvcreate "$DEVICE"
                    sudo vgcreate "$VG_NAME" "$DEVICE"
                    sudo lvcreate -L "$SIZE" -n "$LV_NAME" "$VG_NAME"
                    sudo mkfs.ext4 "/dev/$VG_NAME/$LV_NAME"
                    sudo mount "/dev/$VG_NAME/$LV_NAME" /mnt/lvm_storage
                    dialog --msgbox "LVM Volume Created Successfully!" 7 50
                    ;;
                2)
                    LV_PATH=$(dialog --inputbox "Enter Logical Volume Path (e.g., /dev/my_vg/my_lv):" 8 40 3>&1 1>&2 2>&3)
                    SIZE=$(dialog --inputbox "Enter size to increase (e.g., +5G):" 8 40 3>&1 1>&2 2>&3)
                    sudo lvextend -L "$SIZE" "$LV_PATH"
                    sudo resize2fs "$LV_PATH"
                    dialog --msgbox "LVM Volume Extended Successfully!" 7 50
                    ;;
                3)
                    LVM_DETAILS=$(lvdisplay)
                    dialog --msgbox "$LVM_DETAILS" 20 60
                    ;;
                4) exit ;;
            esac
            ;;
        7) exit ;;
    esac
done

