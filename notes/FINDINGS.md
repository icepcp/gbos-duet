# GBOS -> Lenovo Chromebook Duet (krane, MT8183) feasibility — 2026-11-01

Source: mica-user/16471258 recovery.zip (sha256 cb68dd6d…, matches gbos-vm pin)
Extracted: ~/gbos-duet/dl/mica.raw, super/*.img, mounted at /mnt/gb/* (loop, ro; not persistent across reboot)
Tools: ~/gbos-duet/scripts/lpunpack.py, isa_scan.sh

## Blocker: CPU ISA
- build.prop: ro.bionic.cpu_variant=cortex-a55, dalvik.vm.isa.arm64.variant=cortex-a55 (=> armv8.2-a)
- MT8183 = Cortex-A73 + A53 = ARMv8.0-A: no LSE atomics, no LDAPR (RCpc), no dotprod.
- 962 / 2484 ELFs in system+vendor contain non-NOP v8.1+ instructions (PAC/BTI are NOP-space, ignored).
- Inlined, not runtime-dispatched: RefBase::incStrong (libutils) uses `ldadd`;
  libbinder transact; init; runtime APEX linker64 (ldapr x350, LSE x500+) and bionic libc.
- => Stock image SIGILLs in first-stage init / the dynamic linker on the Duet.

## Possible workarounds
1. Kernel undef-hook emulation of LSE/LDAPR/SDOT/UDOT/RETAA (slow: trap per atomic).
2. Static binary rewrite: LDAPR->LDAR in place (same size, stronger semantics);
   LSE -> branch to LL/SC trampolines in an added segment. Must cover APEX payloads
   (re-sign / replace apex keys), vendor, APK native libs. Big but performant.
3. Hybrid: in-place LDAPR->LDAR + kernel emulation for LSE.
Plus ART: override dalvik.vm.isa.arm64.variant to cortex-a53 and recompile boot image.

## Other known issues (from earlier research)
4 GB RAM; Mali-G72 Panfrost/no usable Vulkan for Chrome; HALs for wifi/audio/sensors.

## Other images (2026-11-01, catalog: production_recovery.json)
- Real Googlebooks: lapis/moonstone/ruby = x86_64; mica (Dell) + quartz (HP) = arm64, BOTH cortex-a55 (quartz libutils byte-identical to mica).
- **Android Studio "Google APIs Desktop (Preview)" arm64-v8a API 37.1 r01** (dl.google.com/android/repository/sys-img/android-desktop/arm64-v8a-37.1_r01.zip, build CLE3.260929.004 desktop_generic-userdebug, dev-keys):
  cpu_variant=generic; LSE only inside outline-atomic helpers guarded by runtime check (cbz w16).
  Only 5 files w/ "unguarded" hits (1-19 each, likely data-in-text). => runs on ARMv8.0.
  Unpacked at dl/emu/arm64-v8a, mounted /mnt/emu/*.
- It lacks GBOS shell/apps: SystemUITitan, NexusLauncherRelease, SettingsGoogle, SetupWizardDesktop, GeminiShell, ContextualCursor, TaskManager, etc.
  Their native libs are v8.0-clean (only TFLite in SystemUITitan has 164 hits - check dispatch). Chrome/Trichrome clean.
  SystemUITitan/SettingsGoogle/TaskManager signed w/ mica platform key -> must re-sign with AOSP test platform key (emu uses dev-keys).
- Plan candidate: base = emulator image (system/system_ext/product/APEX) + graft mica GBOS apps (re-signed) + Duet kernel/vendor.

## QEMU graft test (2026-11-01) — scripts in ~/gbos-duet/scripts
- No KVM → QEMU 6.2 TCG, -cpu cortex-a72 (ARMv8.0, NO LSE = Duet-equivalent ISA), virt, virtio-gpu-pci 2D.
- Graphics: emulator vendor ranchu HWC3 with ro.vendor.hwcomposer.mode=client + display_finder_mode=drm,
  minigbm gralloc, ANGLE (system) on SwiftShader vulkan.pastel.so (from Cuttlefish com.google.cf.vulkan apex). Works (ANGLE reports SwiftShader Vulkan 1.3) but VERY slow under TCG.
- Disk: single GPT (vbmeta, super, metadata, userdata); fstab patched to /dev/block/by-name/*; super built by scripts/lpmake.py; staged partitions packed as ext4 (fstab accepts ext4).
- Removed sensors multihal (crash-loops w/o emulator host). adb: vendor/bin/gbos-net.sh sets static IP; hostfwd 127.0.0.1:5555. Host adb key baked into initrd /adb_keys.
- Stock emulator image boots on v8.0 CPU: ZERO SIGILL. SystemUI starts (boot_completed slow, >25 min under TCG+SwiftShader).
- Graft (scripts/graft.sh): system=emu, system_ext=emu minus SystemUI/Launcher3/Settings/GoogleSdkSetup + mica SystemUITitan, SettingsGoogle, NexusLauncherRelease, SetupWizardDesktop, etc + mica permissions/sysconfig/overlay; product=mica whole (emu product/etc/selinux kept).
  Emulator dev-keys != AOSP test keys, so ALL build-key APKs on both sides re-signed with AOSP test keys (platform/testkey/shared/media) and plat_mac_permissions.xml platform cert patched.
  Gotcha: do NOT re-sign networkstack (e0d4…) — shares UID with APEX-embedded apps (tethering, cellbroadcast) → system_server "Signature mismatch" crash.
- Serial: build/out/serial.sock (scripts/gsh.py 'cmd' runs as root); monitor build/out/mon.sock (screendump).

## KEY RESULT: hybrid "real GBOS Java framework on v8.0 natives" (2026-11-01 ~19:00)
- GBOS is not just apps: mica services.jar 35MB vs emu 26MB, plus system_server jar desktop-services.jar (7MB, e.g. DesktopDeviceStatePolicy).
  Graft-only (emu framework) crashed: ClassNotFound com.android.server.desktop.power.DesktopDeviceStatePolicy$Provider (from mica overlay config).
- JNI check (notes/jni/dexnatives.py, custom dex parser; Ubuntu dexdump too old): emu natives register 5195 methods, ALL present w/ identical
  signatures in mica framework/services/framework-graphics. mica adds only 21 (brotli, ukey2, trusttoken, desktop ProfileDetectionService).
  => mica Java framework + emu (v8.0) native libs is ABI-compatible at JNI boundary.
- scripts/hybrid.sh: mica system/framework (jars+framework-res, preopt dropped), mica classpaths pbs, app oat dirs removed,
  mica-only libdesktop_power_jni (Rust, v8.0-clean) + rust deps, mica etc/permissions+sysconfig (minus strict-signature xml).
- Result: mica system_server + desktop-services runs on cortex-a72 TCG with NO crashes for 30+ min; doing first-boot dexopt
  (~15s/package under TCG). SystemUITitan launch pending.
- Build order: graft.sh -> hybrid.sh -> rebuild.sh -> run_qemu.sh (MEM=8192).

## Next steps
1. Finish QEMU boot → confirm SystemUITitan/NexusLauncher render (screendump via mon.sock).
2. Measure RAM at idle (target: fits Duet 4GB?).
3. Duet: mainline/ChromeOS MT8183 kernel w/ Android configs (binder, etc.), vendor = emu vendor minus ranchu bits
   + Mesa panfrost (GL) / SwiftShader fallback, drm_hwcomposer, depthcharge-signed kernel partition, boot from USB.

## State at pause (2026-11-02, weekly usage 96%)
- Hybrid boot blocker #1 found: DesktopRepairModeService (registered via product/overlay/DesktopServicesOverlay.apk) blocks boot phase
  in ServiceManager.waitForService("vendor.google.desktop.vpd_executor.IVpdExecutor/default") -> watchdog kills system_server after ~180s.
- Fix attempted: copied mica Rust HAL vendor.google.desktop.vpd_executor.vpd-executor (v8.0-clean) + its own Rust dylibs into
  /vendor/lib64/gbos (LD_LIBRARY_PATH wrapper in /vendor/etc/init/vpd-executor.rc, seclabel su) + vintf fragment.
  After that boot (data kept via KEEP_META/KEEP_DATA), watchdog sysrq dumps were still seen; adb went offline and the serial shell hung,
  so NOT yet confirmed whether the VPD HAL started or a different service blocks now.
- Resume: kill VM, boot again (MEM=8192, KEEP_* data), then check: getprop init.svc.vendor.google.desktop.vpd_executor.vpd-executor,
  newest /data/anr/* for waitForServiceNative callers, logcat "Since '...' could not be found".
  Fallback if more vendor-only desktop HALs block: patch DesktopServicesOverlay to drop those services, or stub the AIDL services.
