#!/bin/bash
# build_qemu_disk.sh: assemble out/disk.raw + out/initrd.img from staged partitions.
# Partitions come from $B/parts/<name>.img (prepared beforehand). Data/metadata created fresh.
set -euo pipefail
B=~/gbos-duet/build; E=~/gbos-duet/dl/emu/arm64-v8a; O=$B/out; mkdir -p $O
# super
args=(); for p in system system_ext product vendor system_dlkm; do args+=("$p=$B/parts/$p.img"); done
python3 -I ~/gbos-duet/scripts/lpmake.py $O/super.img "${args[@]}"
SUPER=$(stat -c %s $O/super.img)
# metadata + userdata
rm -f $O/metadata.img $O/userdata.img
mkfs.ext4 -q -F -L metadata $O/metadata.img 16M
truncate -s 8G $O/userdata.img; mkfs.ext4 -q -F -O encrypt,verity,quota -L userdata -b 4096 $O/userdata.img
# disk
MB=$((1<<20)); SS=$(( (SUPER+MB-1)/MB ))
rm -f $O/disk.raw; truncate -s $(( (1 + 1 + SS + 16 + 8192 + 2) * MB )) $O/disk.raw
sgdisk -Z $O/disk.raw >/dev/null
sgdisk -n1:1M:+1M -c1:vbmeta -n2:0:+${SS}M -c2:super -n3:0:+16M -c3:metadata -n4:0:+8G -c4:userdata $O/disk.raw >/dev/null
st(){ sgdisk -i $1 $O/disk.raw | awk '/First sector/{print $3}'; }
dd if=$E/system.img of=$O/disk.raw bs=512 skip=2048 seek=$(st 1) count=2048 conv=notrunc status=none
dd if=$O/super.img of=$O/disk.raw bs=1M seek=$(( $(st 2)/2048 )) conv=notrunc,sparse status=none
dd if=${KEEP_META:-$O/metadata.img} of=$O/disk.raw bs=1M seek=$(( $(st 3)/2048 )) conv=notrunc status=none
dd if=${KEEP_DATA:-$O/userdata.img} of=$O/disk.raw bs=1M seek=$(( $(st 4)/2048 )) conv=notrunc,sparse status=none
rm -f $O/super.img $O/metadata.img $O/userdata.img
# initrd: emulator ramdisk with fstab pointed at by-name
R=$B/rd; sudo rm -rf $R; mkdir -p $R
python3 -I ~/gbos-duet/scripts/cpio_list.py $E/ramdisk.cpio $R >/dev/null
sed -i -e 's#^/dev/block/vdc #/dev/block/by-name/userdata #' -e 's#^/dev/block/platform/a003c00.virtio_mmio/by-name/metadata#/dev/block/by-name/metadata#' $R/first_stage_ramdisk/fstab.ranchu
mkdir -p $R/dev $R/proc $R/sys; cp ~/.android/adbkey.pub $R/adb_keys; chmod 644 $R/adb_keys
(cd $R && find . | sort | cpio -o -H newc -R 0:0 --quiet) > $O/initrd.img
ls -lh $O
