#!/bin/bash

# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog is required but not installed. Please install it."
    exit 1
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
show_error() {
    dialog --msgbox "${RED}Error: $1${NC}" 8 60
}

show_success() {
    dialog --msgbox "${GREEN}$1${NC}" 8 60
}

show_warning() {
    dialog --msgbox "${YELLOW}Warning: $1${NC}" 8 60
}

get_input() {
    dialog --inputbox "$1" 10 50 3>&1 1>&2 2>&3
}

validate_size() {
    [[ $1 =~ ^\+?[0-9]+[GM]$ ]] && return 0
    show_error "Invalid size format (use e.g., 1G or +1G)"
    return 1
}

validate_device() {
    local dev=$1

    # Check if device exists
    if [[ ! -b "$dev" ]]; then
        show_error "Device $dev does not exist"
        return 1
    fi

    # Check if device is in use as swap
    if swapon --show | grep -q "$dev"; then
        show_warning "Device $dev is in use as swap. Disable swap first with: swapoff $dev"
        return 1
    fi

    # Check if device is mounted
    if mount | grep -q "$dev"; then
        show_warning "Device $dev is mounted. Unmount it first."
        return 1
    fi

    # Check if device has a filesystem
    if blkid "$dev" | grep -q "TYPE="; then
        show_warning "Device $dev has a filesystem. Wipe it with: wipefs -a $dev (this will erase data)"
        return 1
    fi

    # Check if device is already a physical volume
    if pvdisplay "$dev" &> /dev/null; then
        show_warning "Device $dev is already a physical volume in LVM"
        return 1
    fi

    return 0
}

# Display functions
show_disk_usage() {
    local header="Disk Usage Information\n"
    header+="==============================================================================================\n"
    header+="Filesystem                                                    Size      Used     Avail    Use%\n"
    header+="==============================================================================================\n"

    local output=""
    while read -r line; do
        if [[ $line == Filesystem* ]] || [[ -z $line ]]; then
            continue
        fi
        
        read -r fs size used avail use mount <<< "$line"
        
        # Handle multi-line entries
        if [[ -z $mount ]]; then
            read -r next_line
            line="$line $next_line"
            read -r fs size used avail use mount <<< "$line"
        fi
        
        # Truncate long names
        fs=${fs:0:34}
        mount=${mount:0:24}
        
        output+=$(printf "%-36s%-10s%-10s%-10s%-8s%-26s\n" "$fs" "$size" "$used" "$avail" "$use" "$mount")
    done < <(df -h)
    
    dialog --msgbox "$header$output" 30 100
}

show_physical_volumes() {
    local header="Physical Volume Information\n"
    header+="================================================================================\n"
    header+="PV Name                           VG Name           PV Size     PV Free  \n"
    header+="================================================================================\n"

    if ! command -v pvdisplay &> /dev/null; then
        show_error "pvdisplay command not found. LVM may not be installed."
        return
    fi

    local output
    output="$header$(pvdisplay -C -o pv_name,vg_name,pv_size,pv_free --separator " " | awk 'NR>1 {printf "%-30s %-15s %-12s %-12s\n", $1, $2, $3, $4}')"

    dialog --msgbox "$output" 30 100
}

show_volume_groups() {
    local header="Volume Group Information\n"
    header+="================================================================================\n"
    header+="VG Name                           VG Size     VG Free      #PVs    #LVs   \n"
    header+="================================================================================\n"
    if ! command -v vgdisplay &> /dev/null; then
        show_error "vgdisplay command not found. LVM may not be installed."
        return
    fi

    local output
    output="$header$(vgdisplay -C -o vg_name,vg_size,vg_free,pv_count,lv_count --separator " " | awk 'NR>1 {printf "%-30s %-12s %-12s %-8s %-8s\n", $1, $2, $3, $4, $5}')"

    dialog --msgbox "$output" 30 100
}

show_logical_volumes() {
    local header="Logical Volume Information\n"
    header+="================================================================================\n"
    header+="LV Name                           VG Name           LV Size    LV Path\n"
    header+="================================================================================\n"

    if ! command -v lvdisplay &> /dev/null; then
        show_error "lvdisplay command not found. LVM may not be installed."
        return
    fi

    local output
    output="$header$(lvdisplay -C -o lv_name,vg_name,lv_size,lv_path --separator " " | awk 'NR>1 {printf "%-30s %-15s %-12s %-s\n", $1, $2, $3, $4}')"
    dialog --msgbox "$output" 30 100
}


create_lvm_volume() {
    local VG LV SIZE DEV

    # Get user input
    VG=$(get_input "Volume Group Name (e.g., myvg):")
    [[ -z "$VG" ]] && { show_error "Volume Group Name cannot be empty"; return; }

    LV=$(get_input "Logical Volume Name (e.g., mylv):")
    [[ -z "$LV" ]] && { show_error "Logical Volume Name cannot be empty"; return; }

    SIZE=$(get_input "Size (e.g., 1G):")
    validate_size "$SIZE" || return

    DEV=$(get_input "Device (e.g., /dev/sdb):")
    validate_device "$DEV" || return

    # Create PV
    if ! pvcreate "$DEV" >/dev/null 2>&1; then
        show_error "Failed to create physical volume on $DEV"
        return
    fi

    # Create VG
    if ! vgcreate "$VG" "$DEV" >/dev/null 2>&1; then
        show_error "Failed to create volume group $VG"
        pvremove "$DEV" >/dev/null 2>&1
        return
    fi

    # Create LV
    if ! lvcreate -L "$SIZE" -n "$LV" "$VG" >/dev/null 2>&1; then
        show_error "Failed to create logical volume $LV"
        vgremove -f "$VG" >/dev/null 2>&1
        pvremove "$DEV" >/dev/null 2>&1
        return
    fi

    # Format with ext4
    if ! mkfs.ext4 "/dev/$VG/$LV" >/dev/null 2>&1; then
        show_warning "Created LVM volume but failed to format it. Path: /dev/$VG/$LV"
        return
    fi

    show_success "LVM Volume created and formatted successfully!\nPath: /dev/$VG/$LV\nSize: $SIZE"
}

extend_lvm_volume() {
    local LV SIZE VG

    # Get user input
    LV=$(get_input "Logical Volume Path (e.g., /dev/myvg/mylv):")
    [[ ! -b "$LV" ]] && { show_error "Invalid logical volume path"; return; }

    SIZE=$(get_input "Size to add (e.g., +1G):")
    validate_size "$SIZE" || return

    # Get VG name
    VG=$(dirname "$LV" | xargs basename)

    # Extend LV
    if ! lvextend -L "$SIZE" "$LV" >/dev/null 2>&1; then
        show_error "Failed to extend logical volume $LV"
        return
    fi

    # Resize filesystem
    if ! resize2fs "$LV" >/dev/null 2>&1; then
        show_warning "Extended volume but failed to resize filesystem. Manual resize needed."
        return
    fi

    show_success "LVM Volume extended successfully!\nNew size: $(lvs --noheadings -o lv_size "$LV" | tr -d ' ')"
}

# Main menu
while true; do
    CHOICE=$(dialog --menu "LVM Management Dashboard" 17 55 9 \
        1 "Show Disk Usage" \
        2 "Show Physical Volumes" \
        3 "Show Volume Groups" \
        4 "Show Logical Volumes" \
        5 "Create LVM Volume" \
        6 "Extend LVM Volume" \
        7 "Exit" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) show_disk_usage ;;
        2) show_physical_volumes ;;
        3) show_volume_groups ;;
        4) show_logical_volumes ;;
        5) create_lvm_volume ;;
        6) extend_lvm_volume ;;
        7) exit 0 ;;
        *) show_error "Invalid option" ;;
    esac
done
