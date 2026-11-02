#!/bin/bash
# rebuild.sh: repack staged partitions (stage/<p> -> parts/<p>.img for each staged dir) and the disk.
set -euo pipefail
B=~/gbos-duet/build; cd $B
for d in stage/*/; do p=$(basename $d)
  kb=$(sudo du -sk --apparent-size "$d" | cut -f1); sz=$(( kb*115/100/1024 + 48 ))
  rm -f parts/$p.img; truncate -s ${sz}M parts/$p.img
  sudo mkfs.ext4 -q -F -O ^has_journal -L $p -E root_owner=0:0 -d "$d" parts/$p.img; sudo chown $USER parts/$p.img
  echo "packed $p ${sz}M"
done
~/gbos-duet/scripts/build_qemu_disk.sh
