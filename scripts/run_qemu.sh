#!/bin/bash
# run_qemu.sh: boot out/disk.raw on TCG, Cortex-A72 (ARMv8.0, no LSE) like the Duet's A73/A53, 4GB RAM.
# Serial: out/serial.sock (log: out/serial.log). Monitor: out/mon.sock. VNC: localhost:5901.
B=~/gbos-duet/build; O=$B/out; E=~/gbos-duet/dl/emu/arm64-v8a
KERNEL=${KERNEL:-$E/kernel-ranchu}
CMD="console=ttyAMA0 earlycon printk.devkmsg=on loglevel=1 androidboot.console=ttyAMA0 androidboot.hardware=ranchu \
androidboot.boot_devices=a003e00.virtio_mmio androidboot.selinux=${SELINUX:-permissive} androidboot.serialno=GBOSDUET01 \
androidboot.verifiedbootstate=orange androidboot.qemu=1 qemu=1 androidboot.lcd.density=160 \
androidboot.hardware.gralloc=minigbm androidboot.hardwareegl=angle androidboot.hardware.vulkan=pastel \
androidboot.debug.hwui.renderer=skiagl androidboot.opengles.version=196610 ${EXTRA_CMDLINE:-}"
rm -f $O/serial.sock $O/mon.sock
exec qemu-system-aarch64 -M virt,gic-version=3 -accel tcg,thread=multi -cpu ${CPU:-cortex-a72} -smp 8 -m ${MEM:-4096} \
  -kernel $KERNEL -initrd $O/initrd.img -append "$CMD" \
  -drive if=none,id=d0,file=$O/disk.raw,format=raw,cache=unsafe -device virtio-blk-device,drive=d0 \
  -device virtio-gpu-pci,xres=1280,yres=800,edid=on -device virtio-keyboard-pci -device virtio-tablet-pci \
  -device virtio-rng-pci -netdev user,id=n0,hostfwd=tcp:127.0.0.1:5555-:5555 -device virtio-net-pci,netdev=n0 \
  -chardev socket,id=s0,path=$O/serial.sock,server=on,wait=off,logfile=$O/serial.log -serial chardev:s0 \
  -monitor unix:$O/mon.sock,server,nowait -display none -vnc 127.0.0.1:1
