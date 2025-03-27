#!/bin/sh
# Save as bitpixie-motd.sh

VERSION="1.14"
DEVICE_NAME="$(cat /sys/class/dmi/id/sys_vendor) $(cat /sys/class/dmi/id/product_family ) $(cat /sys/class/dmi/id/product_name)"

echo -e "\e[1;36m==== BitPixie Exploit $VERSION ====\e[0m"
echo -e "\e[1;33mDEVICE INFORMATION:\e[0m"
echo -e "    \e[32mDevice name:\e[0m $DEVICE_NAME"
echo
echo -e "\e[1;33mRUNNING THE EXPLOIT:\e[0m"
echo "Basic usage:"
echo -e "    \e[35mrun-exploit\e[0m"
echo "This will extract the VMK in both binary (VMK.dat) and ASCII (VMK.txt) format"
echo
echo -e "\e[1;33mAVAILABLE OPTIONS:\e[0m"
echo -e "    \e[35m-t --no-transfer\e[0m    Do not transfer the VMK to the attacker server"
echo -e "    \e[35m-m --mount <disk>\e[0m   Mount the target disk to /root/mnt"
echo

echo -e "\e[1;33mDETECTED WINDOWS PARTITIONS:\e[0m"
windows_partitions=$(fdisk -l 2>/dev/null | grep "Microsoft basic data" | cut -d' ' -f1)
if [ -z "$windows_partitions" ]; then
  echo -e "    \e[31mNo Windows partitions detected\e[0m"
else
  echo -e "    \e[32mFound potential target(s):\e[0m"
  echo "$windows_partitions" | while read line; do
    echo -e "    \e[32m$line\e[0m"
  done
fi

echo
echo -e "\e[1;33mTROUBLESHOOTING:\e[0m"
echo "If no Windows partition is detected automatically,"
echo "try manual disk identification:"
echo -e "    \e[35mlsblk -f\e[0m"
echo
echo -e "\e[1;36m================================\e[0m"
