#!/bin/bash

# This script will create and fire up a standard debian buster lxc container on your Proxmox VE.
# On a Proxmox cluster, the script will create the container on the local node, where it's executed.
# The container ID will be automatically assigned by increasing (+1) the highest number of
# existing LXC containers in your environment. If the assigned ID is already taken by a VM
# or no containers exist yet, the script falls back to the ID 100.

# Original bashclub authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <m.helmke@nettwarker.de>
# (C) 2021 Script rework and documentation by Thorsten Spille <thorsten@spille-edv.de>

# Forked and modified by:
# Thomas Rathert <098urm69v@mozmail.com>

# IMPORTANT NOTE:
# Please adjust th settings in 'zamba.conf' to your needs before running the script

############### ZAMBA INSTALL SCRIPT ###############
prog="$(basename "$0")"

usage() {
	cat >&2 <<-EOF
	usage: $prog [-h] [-i CTID] [-s SERVICE] [-c CFGFILE]
	  installs a preconfigured lxc container on your proxmox server
    -i CTID      provide a container id instead of auto detection
    -s SERVICE   provide the service name and skip the selection dialog
    -c CFGFILE   use a different config file than 'zamba.conf'
    -h           displays this help text
  -----------------------------------------------------------------------------------------
    (C) 2021     forked from bashclub zamba-lxc-toolbox by ThRat (https://github.com/ThRat)
  -----------------------------------------------------------------------------------------

	EOF
	exit $1
}

ct_id=0
undefined="<undefined>"
service=$undefined
config=$undefined
default_config=$PWD/conf/zamba.conf
verbose=0

while getopts "hi:s:c:" opt; do
  case $opt in
    h) usage 0 ;;
    i) ct_id=$OPTARG ;;
    s) service=$OPTARG ;;
    c) config=$OPTARG ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND-1))

# list folders for available services list
available_svcs=($(ls -d $PWD/src/*/ | grep -v __ | xargs basename -a))

# use given container id (via command line opts) or if already existing the next free id
if  [ "$ct_id" -lt 100 ] || [ -f "/etc/pve/qemu-server/$ct_id.conf" ]; then
  ct_id=$(pvesh get /cluster/nextid | xargs );
fi

# interactive main menu
valid=0
if [[ "$service" == "$undefined" ]]; then
  while true
  do
  main_menu_choice=$(
  whiptail --title "Operative Systems" --menu "Make your choice" 16 100 9 \
    "1)" "Configure service container to install"  \
    "2)" "Show configured values" \
    "3)" "Install container" \
    "4)" "End interactive mode and display help on batch usage" 3>&2 2>&1 1>&3	
  )
  exitstatus=$?

  # handle menu choice
  case $main_menu_choice in
    "1)")   
      # -------------------------------------------------
      # sub dialogs for defining config file path
      # -------------------------------------------------
      config=$(whiptail --title "Base config" --inputbox "Contig path to use:" 0 78 "$default_config"  3>&1 1>&2 2>&3)
      exitstatus=$?
      if [ $exitstatus = 0 ]; then
        if [ ! -f "$config" ]; then
          err_msg_no_config="File $config not does not exist!\n\n"
          err_msg_no_config+="CREATE A CONFIG file first, before running this script again.\n\n"
          err_msg_no_config+="Exiting..."
          whiptail --title "Error: no config file" --msgbox "$err_msg_no_config" 0 0
          exit
        fi
      else
        continue
      fi

      # -------------------------------------------------
      # sub dialog for defining Container ID to use
      # -------------------------------------------------
      msg_ct_id="Container Id to use? (next available id: $ct_id)"
      ct_id=$(whiptail --title "Proxmox Container ID" --inputbox "$msg_ct_id" 0 0 "$ct_id"  3>&1 1>&2 2>&3)
      exitstatus=$?
      # back to main menu on dialog cancel
      if [ $exitstatus = 1 ]; then
        continue
      fi

      # -------------------------------------------------
      # Menu dialog to choose service to install
      # -------------------------------------------------
      menu_choices=();
      for key in "${!available_svcs[@]}";
      do
          menu_choices+=("${available_svcs[$key]}" "    ($key)");
      done;
      checklist_choices=();
      for key in "${!available_svcs[@]}";
      do
          checklist_choices+=("${available_svcs[$key]}" "$key" ""); # last entry in array is default on or off
      done;
      msg_svc_choice="Select service container to install"
      service=$(whiptail --title "Service choice" --menu "$msg_svc_choice" 0 0 0 -- "${menu_choices[@]}" 3>&1 1>&2 2>&3)
      exitstatus=$?
      # back to main menu on dialog cancel
      if [ $exitstatus = 1 ]; then
        continue
      fi
      #service=$(whiptail --title "Service choice (select with space)" --checklist \
      #"Select service container to install" 0 0 0 -- "${choices2[@]}" 3>&1 1>&2 2>&3)
    ;;

    "2)") 
      whiptail --title "Configuration for service installation" \
               --msgbox "Config:  $config \nCT ID:   $ct_id \nService: $service" 0 0
    ;;

    "3)") 
      if [ "$service" == "$undefined" ] || [ ! -f "$config" ]; then
        whiptail --title "ERROR: no service to install" --msgbox "Configure service container to install first!" 0 0
        continue # back to main menu
      else
        whiptail --title "Install service" --yesno "Installing now service container: $service" \
                 --yes-button "Continue" --no-button "Cancel" 0 0
        exitstatus=$?
        # back to main menu on dialog cancel
        if [ $exitstatus = 0 ]; then
          break # end main menu loop and continue this script
        else
          continue # back to main menu
        fi
      fi
    ;;

    "4)")   
      usage
      break
    ;;

  esac

  # exit main menu loop on Cancel
  if [[ $exitstatus = 1 ]]; then
    break; 
  #else 
  #  whiptail --msgbox "Nothing selected, return to main menu."
  fi
  done
  
  #select svc in $available_svcs quit; do
    # if [[ "$svc" != "quit" ]]; then
    #    for line in $(echo $available_svcs); do
    #     if [[ "$svc" == "$line" ]]; then
    #       service=$svc
    #       echo "Installation of $service selected."
    #       valid=1
    #       break
    #     fi
    #   done
   # else
   #   echo "Selected 'quit' exiting without action..."
   #   exit 0
   # fi
   # if [[ "$valid" == "1" ]]; then
   #   break
   # fi
  #done
else
  for line in "${available_svcs[@]}" 
  do
    if [[ "$service" == "$line" ]]; then
      echo "Installation of $service selected."
      valid=1
      break
    fi
  done
fi

if [[ "$valid" != "1" ]]; then
  echo "Invalid option, exiting..."
  usage 1
fi

# Load configuration file
echo "Loading config file '$config'..."
# shellcheck source-path=./conf
source "$config"

source $PWD/src/$service/constants-service.conf

# CHeck is the newest template available, else download it.
DEB_LOC=$(pveam list $LXC_TEMPLATE_STORAGE | grep $LXC_TEMPLATE_VERSION | cut -d'_' -f2)
DEB_REP=$(pveam available --section system | grep $LXC_TEMPLATE_VERSION | cut -d'_' -f2)

if [[ $DEB_LOC == $DEB_REP ]];
then
  echo "Newest Version of $LXC_TEMPLATE_VERSION $DEP_REP exists.";
else
  echo "Will now download newest $LXC_TEMPLATE_VERSION $DEP_REP.";
  pveam download $LXC_TEMPLATE_STORAGE "$LXC_TEMPLATE_VERSION"_$DEB_REP\_amd64.tar.gz
fi


echo "Will now create LXC Container $ct_id!";

# Create the container
pct create $ct_id -unprivileged $LXC_UNPRIVILEGED $LXC_TEMPLATE_STORAGE:vztmpl/"$LXC_TEMPLATE_VERSION"_$DEB_REP\_amd64.tar.gz -rootfs $LXC_ROOTFS_STORAGE:$LXC_ROOTFS_SIZE;
sleep 2;

# Check vlan configuration
if [[ $LXC_VLAN != "" ]];then VLAN=",tag=$LXC_VLAN"; else VLAN=""; fi
# Reconfigure conatiner
pct set $ct_id -memory $LXC_MEM -swap $LXC_SWAP -hostname $LXC_HOSTNAME -onboot 1 -timezone $LXC_TIMEZONE -features nesting=$LXC_NESTING;
if [ $LXC_DHCP == true ]; then
 pct set $ct_id -net0 name=eth0,bridge=$LXC_BRIDGE,ip=dhcp,type=veth$VLAN;
else
 pct set $ct_id -net0 name=eth0,bridge=$LXC_BRIDGE,firewall=1,gw=$LXC_GW,ip=$LXC_IP,type=veth$VLAN -nameserver $LXC_DNS -searchdomain $LXC_DOMAIN;
fi
sleep 2

if [ $LXC_MP -gt 0 ]; then
  pct set $ct_id -mp0 $LXC_SHAREFS_STORAGE:$LXC_SHAREFS_SIZE,mp=/$LXC_SHAREFS_MOUNTPOINT
fi
sleep 2;

PS3="Select the Server-Function: "

pct start $ct_id;
sleep 5;
# Set the root password and key
echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$ct_id passwd;
lxc-attach -n$ct_id mkdir /root/.ssh;
pct push $ct_id $LXC_AUTHORIZED_KEY /root/.ssh/authorized_keys
pct push $ct_id $config /root/zamba.conf
pct push $ct_id $PWD/src/constants.conf /root/constants.conf
pct push $ct_id $PWD/src/lxc-base.sh /root/lxc-base.sh
pct push $ct_id $PWD/src/$service/install-service.sh /root/install-service.sh
pct push $ct_id $PWD/src/$service/constants-service.conf /root/constants-service.conf

echo "Installing basic container setup..."
lxc-attach -n$ct_id bash /root/lxc-base.sh
echo "Install '$service'!"
lxc-attach -n$ct_id bash /root/install-service.sh

if [[ $service == "zmb-ad" ]]; then
  pct stop $ct_id
  pct set $ct_id \-nameserver $(echo $LXC_IP | cut -d'/' -f 1)
  pct start $ct_id
fi
