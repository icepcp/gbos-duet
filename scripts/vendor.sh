#!/bin/bash
# vendor.sh: stage the vendor partition for the QEMU test build (build/stage/vendor).
# Base = Android Studio "Google APIs Desktop" API 37.1 arm64 emulator vendor (ranchu), changed for
# plain QEMU (no Android Emulator host) + the one mica vendor HAL Googlebook system_server waits for.
# Needs mounted (read-only): /mnt/emu/vendor, /mnt/cf/vk (Cuttlefish com.google.cf.vulkan payload), /mnt/gb/vendor_a.
set -euo pipefail
B=$HOME/gbos-duet/build; SV=$B/stage/vendor; MV=/mnt/gb/vendor_a
mkdir -p $B/stage; sudo rm -rf $SV; sudo cp -a /mnt/emu/vendor $SV

# 1. Guest-side rendering: SwiftShader Vulkan (from Cuttlefish) under ANGLE, ranchu HWC3 in client mode on virtio-gpu.
sudo cp -a /mnt/cf/vk/lib64/hw/vulkan.pastel.so $SV/lib64/hw/vulkan.pastel.so
sudo tee -a $SV/build.prop >/dev/null <<'EOF'
# gbos-duet: guest (software) rendering under plain QEMU
ro.vendor.hwcomposer.mode=client
ro.vendor.hwcomposer.display_finder_mode=drm
ro.hardware.vulkan=pastel
ro.hardware.egl=angle
ro.hardware.gralloc=minigbm
debug.hwui.renderer=skiagl
service.adb.tcp.port=5555
debug.sf.nobootanimation=1
EOF

# 2. Single GPT disk: data/metadata by partition name (initrd fstab gets the same edit in build_qemu_disk.sh).
sudo sed -i -e 's#^/dev/block/vdc #/dev/block/by-name/userdata #' \
  -e 's#^/dev/block/platform/a003c00.virtio_mmio/by-name/metadata#/dev/block/by-name/metadata#' $SV/etc/fstab.ranchu

# 3. Sensors multihal aborts in a loop without the emulator host -> remove service + VINTF declaration.
sudo rm -f $SV/etc/init/android.hardware.sensors-service-multihal.rc $SV/etc/vintf/manifest/android.hardware.sensors-multihal.xml

# 4. adb over QEMU user-net: static IP on eth0 (emulator normally drives it via virtio-wifi).
sudo tee $SV/bin/gbos-net.sh >/dev/null <<'EOF'
#!/system/bin/sh
# gbos-duet test harness: static IP on QEMU user-net so host adb can reach adbd on :5555
ip link set eth0 up
ip addr add 10.0.2.15/24 dev eth0
ip rule add from all lookup main pref 1
setprop service.adb.tcp.port 5555
EOF
sudo chmod 755 $SV/bin/gbos-net.sh; sudo setfattr -n security.selinux -v u:object_r:vendor_file:s0 $SV/bin/gbos-net.sh
sudo tee $SV/etc/init/gbos-net.rc >/dev/null <<'EOF'
service gbos-net /vendor/bin/gbos-net.sh
    user root
    group root
    oneshot
    disabled
    seclabel u:r:su:s0

on property:sys.usb.config=adb
    start gbos-net
EOF
sudo setfattr -n security.selinux -v u:object_r:vendor_configs_file:s0 $SV/etc/init/gbos-net.rc

# 5. Googlebook VPD HAL (Rust, ARMv8.0-clean). DesktopRepairModeService blocks boot waiting for
#    vendor.google.desktop.vpd_executor.IVpdExecutor/default. Rust dylibs are toolchain-hash specific,
#    so the HAL gets mica's own dylib set in /vendor/lib64/gbos (never overwrite the emulator's).
P=$SV/lib64/gbos; sudo mkdir -p $P
for l in libvpd_executor_aidl_V1 libtokio libsignal_hook_registry libsocket2 libbytes libmio liberrno \
         liblogger libenv_filter libbinder_rs liblog_rust libstd; do sudo cp -a $MV/lib64/$l.dylib.so $P/; done
sudo cp -a $MV/bin/hw/vendor.google.desktop.vpd_executor.vpd-executor $SV/bin/hw/
sudo cp -a $MV/etc/vintf/manifest/vendor.google.desktop.vpd_executor.vpd-executor.xml $SV/etc/vintf/manifest/
sudo tee $SV/etc/init/vpd-executor.rc >/dev/null <<'EOF'
# gbos-duet: mica Rust HAL with its own Rust dylib set (toolchain-hash specific)
service vendor.google.desktop.vpd_executor.vpd-executor /vendor/bin/sh -c "LD_LIBRARY_PATH=/vendor/lib64/gbos exec /vendor/bin/hw/vendor.google.desktop.vpd_executor.vpd-executor"
    class hal
    user root
    group root system
    interface aidl vendor.google.desktop.vpd_executor.IVpdExecutor/default
    disabled
    oneshot
    seclabel u:r:su:s0
EOF
echo "vendor staged: $SV"
