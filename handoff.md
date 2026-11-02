# Googlebook OS on Lenovo Chromebook Duet — Handoff

Nov 2, 2026 · @myat

## TL;DR

Porting Googlebook OS to the Lenovo Chromebook Duet (MT8183, Cortex-A73/A53, 4 GB) looks feasible but is not done: the CPU blocker is solved, and the real Googlebook system\_server now boots most of the way under QEMU.

- **Goal:** a flashable Googlebook OS image for the user's Duet (codename krane), booted in ChromeOS developer mode.
- **Done:** feasibility research, plus a QEMU test build that runs the real Googlebook framework on an emulated ARMv8.0 CPU (the Duet's ISA level) with zero illegal-instruction crashes.
- **Blocked on:** one Googlebook service, `DesktopRepairModeService`, waits forever for a Dell vendor HAL. That triggers the system\_server watchdog. A fix is built but not yet verified.
- **Not started:** anything on real Duet hardware (kernel, vendor, Panfrost graphics, boot image). RAM use against 4 GB is also unmeasured.
- **Paused because:** weekly Claude usage reached 96%. It resets Nov 5, 3pm UTC.

## Key findings

The stock Googlebook image cannot run on the Duet's CPU. The working approach is a hybrid: the native layer from Google's ARMv8.0 Android Desktop emulator image, plus Googlebook's Java layer, which runs on any CPU.

1. **The real Googlebook images are built for ARMv8.2.** Dell mica (build 16471258) and HP quartz both set `cpu_variant=cortex-a55`. 962 of the 2484 system/vendor ELFs contain inlined LSE atomics and `ldapr`, including `linker64`, bionic libc, `libutils` (`RefBase::incStrong`) and libbinder. The Duet's A73/A53 cores are ARMv8.0, so every process would crash with an illegal instruction (SIGILL).
2. **The other three Googlebooks are x86.** lapis (ASUS), moonstone (Acer) and ruby (Lenovo) don't help.
3. **One image is ARMv8.0-clean:** Android Studio's "Google APIs Desktop (Preview)" arm64 system image, API 37.1 (build CLE3.260929.004, `desktop_generic-userdebug`).
   - Its LSE instructions all sit in outline-atomics helpers behind a runtime check.
   - It booted on QEMU `-cpu cortex-a72` (no LSE) with zero SIGILLs.
   - It's the same Android release, but plain AOSP desktop: no Googlebook shell or services.
4. **Googlebook OS is a forked framework, not just apps.**
   - Mica's `services.jar` is 35 MB, against 26 MB in the emulator.
   - It adds `desktop-services.jar` (7 MB) to system\_server.
   - Grafting the apps alone failed: system\_server couldn't find the class `DesktopDeviceStatePolicy$Provider`.
5. **The JNI boundary matches.** The emulator's native libraries register 5,195 JNI methods, and every one has an identical signature in mica's framework, services and framework-graphics jars. Mica adds only 21: brotli, ukey2, trusttoken and `ProfileDetectionService`.
6. **The hybrid runs.** Emulator native libraries plus mica's Java framework, apps and overlays booted system\_server and desktop-services for 30+ minutes with no crashes, until the watchdog issue below.
7. **Mica's Rust code is ARMv8.0-clean.** That includes `libdesktop_power_jni` and the VPD HAL. Rust dylibs are toolchain-hash-specific, though, so they must ship with their own libstd and companion dylibs.

## Current blocker

system\_server is killed by its watchdog after about 180 s, because a Googlebook service blocks a boot phase waiting for a vendor HAL that the emulator vendor doesn't have.

- **What blocks:** `DesktopRepairModeService.readPostManufacturingConfig` calls `ServiceManager.waitForService("vendor.google.desktop.vpd_executor.IVpdExecutor/default")`, and the call never returns.
- **Where it's registered:** `product/overlay/DesktopServicesOverlay.apk`, a binary resources overlay. It's hard to edit without aapt2.
- **Fix attempted:** copied mica's Rust HAL `vendor.google.desktop.vpd_executor.vpd-executor` into the staged vendor partition.
  - Its own Rust dylib set goes in `/vendor/lib64/gbos`, loaded via an `LD_LIBRARY_PATH` wrapper in `vendor/etc/init/vpd-executor.rc` (seclabel `su`).
  - Its VINTF manifest fragment was added too.
- **Result: unverified.** After that boot (data partitions carried over), the kernel still showed watchdog sysrq dumps. adb then went offline and the serial shell hung, so it's unknown whether the HAL started or a different service is now blocking.
- **Fallback:** if more vendor-only Googlebook HALs block, either drop those services from `DesktopServicesOverlay` or write stub AIDL services.

## Environment and layout

All work lives on a persistent Azure ARM64 VPS (8× Neoverse-N1, 31 GB RAM, about 248 GB disk, Ubuntu 22.04), under `~/gbos-duet`. There's no `/dev/kvm`, so QEMU runs in slow software emulation (TCG).

| Path | What it holds |
| --- | --- |
| `notes/FINDINGS.md` | Running log of every finding, in more detail than this doc |
| `notes/jni/` | `dexnatives.py` (dex native-method parser) and the `emu.txt` / `mica.txt` JNI lists |
| `scripts/` | Build pipeline, lpunpack/lpmake, ISA scanners, QEMU launcher, guest shell helpers |
| `keys/` | AOSP public test keys: platform, testkey, shared, media, networkstack |
| `dl/mica.raw`, `dl/super/` | Dell mica recovery disk and its extracted super partitions |
| `dl/emu/arm64-v8a/` | Unpacked emulator image (`super/`, `kernel-ranchu`, `ramdisk.cpio`) |
| `dl/cf/` | Cuttlefish arm64 image (source of SwiftShader `vulkan.pastel.so`) |
| `build/stage/` | Staged system, system\_ext, product, vendor trees (SELinux xattrs kept) |
| `build/parts/`, `build/out/` | Packed ext4 images; `disk.raw`, `initrd.img`, `serial.log`, sockets, screenshots |

| Download | Source | SHA-256 |
| --- | --- | --- |
| Dell mica recovery 16471258 | [dl.google.com](https://dl.google.com/device/recovery/mica-user/16471258/recovery.zip) | cb68dd6d…a645d7 |
| Emulator Desktop API 37.1 arm64 r01 | [dl.google.com](https://dl.google.com/android/repository/sys-img/android-desktop/arm64-v8a-37.1_r01.zip) | sha1 146d3b4b…10b89 |
| Cuttlefish arm64 16373615 | [ci.android.com](https://ci.android.com/builds/submitted/16373615/aosp_cf_arm64_only_phone-userdebug/latest/aosp_cf_arm64_only_phone-img-16373615.zip) | 051caf80…c85c18 |
| HP quartz recovery 16560795 | [dl.google.com](https://dl.google.com/device/recovery/quartz-user/16560795/recovery.zip) | (compared only, raw deleted) |

The loop mounts under `/mnt/gb`, `/mnt/emu`, `/mnt/cf` and `/mnt/q` don't survive a reboot. Remount them read-only from the images above before re-running `graft.sh`.

## Build pipeline

Four scripts, run in order, turn the downloads into a bootable QEMU disk; each is idempotent over `build/stage/`.

1. `scripts/graft.sh` builds the base tree in `build/stage/`:
   - **system:** the emulator's.
   - **system\_ext:** the emulator's, with AOSP SystemUI, Launcher3, Settings and GoogleSdkSetup swapped for mica's SystemUITitan, SettingsGoogle, NexusLauncherRelease, SetupWizardDesktop and friends, plus mica's permission, sysconfig and overlay files.
   - **product:** mica's whole partition, keeping the emulator's `etc/selinux`.
   - **Signing:** re-signs build-key APKs with AOSP test keys and patches `plat_mac_permissions.xml`.
2. `scripts/hybrid.sh` puts mica's Java layer onto the staged system partition:
   - `system/framework` jars and framework-res, with all preopt code dropped.
   - Mica's `etc/classpaths` protobufs.
   - App `oat/` folders removed.
   - `libdesktop_power_jni` plus its Rust dylibs.
   - Mica's extra permission and sysconfig files, minus the strict-signature list.
3. `scripts/rebuild.sh` packs each `build/stage/<p>` into ext4 under `build/parts/`, then calls `build_qemu_disk.sh`:
   - Builds `super` with `lpmake.py`.
   - Writes a single GPT disk with vbmeta, super, metadata and userdata partitions.
   - Builds an initrd whose fstab points at `/dev/block/by-name/*` and contains the host adb key.
   - Set `KEEP_META=out/keep3.img KEEP_DATA=out/keep4.img` to reuse old data and skip the 30+ minute first-boot dexopt.
4. `scripts/run_qemu.sh` boots it: `MEM=8192 setsid scripts/run_qemu.sh &`.
   - Machine: `virt`, `-cpu cortex-a72` (ARMv8.0, no LSE), 8 vCPUs, virtio-gpu 2D.
   - Graphics: ANGLE on SwiftShader, with the HWC3 composer in `client` mode.

**Inspecting the guest:**

- `python3 scripts/gsh.py '<cmd>' 200` runs a command as root over `build/out/serial.sock`. Only one client can be connected at a time.
- `adb connect 127.0.0.1:5555` works once `gbos-net` sets a static IP. It goes offline whenever system\_server restarts.
- `echo "screendump $PWD/shot.ppm" | socat - UNIX-CONNECT:build/out/mon.sock` grabs the screen. Convert it with PIL.
- `scripts/poll_boot.sh` waits until SystemUI starts, `boot_completed` is set, or system\_server hits a fatal error. It honours `INT=<seconds>`.
- Stop the VM with `pgrep -x qemu-system-aar | xargs kill`. Don't use `pkill -f`, which kills your own shell.

## Gotchas learned

Each of these cost a boot cycle; check them before changing the pipeline.

| Area | Gotcha | What works |
| --- | --- | --- |
| Signing | The emulator uses Google dev-keys, not AOSP test keys | Re-sign all build-key APKs on both sides (cert prefixes are mapped in `graft.sh`) |
| Signing | Re-signing networkstack (`e0d4…`) crashes system\_server with "Signature mismatch" | Leave it alone: it shares a UID with apps inside APEXes (tethering, cellbroadcast) |
| Signing | `preinstalled-packages-strict-signature.xml` pins certificates | Delete it from staged system |
| SELinux | Mica's product sepolicy was compiled against a different platform policy | Keep the emulator's `product/etc/selinux`; boot with `androidboot.selinux=permissive` for now |
| Preopt | Mica's oat/vdex is cortex-a55 code (LSE) | Drop all preopt; ART recompiles on first boot (slow under TCG) |
| Rust | Dylibs are toolchain-hash-specific; mica and emulator `libstd.dylib.so` differ | Give mica Rust binaries their own lib dir; never overwrite the emulator's dylibs |
| HALs | The goldfish sensors multihal aborts with no emulator host | Removed its init rc and VINTF manifest from vendor |
| Graphics | The emulator vendor has only gfxstream (host GPU) | `vulkan.pastel.so` from Cuttlefish, `ro.hardware.egl=angle`, `ro.vendor.hwcomposer.mode=client` |
| Disks | virtio-mmio disk order is hard to predict | One GPT disk, with fstab pointed at `/dev/block/by-name/*` |
| Console | The serial shell hangs when a heavy `logcat` runs under load; `sudo` turns `~` into `/root` | Short commands, absolute paths; restart the VM if the console wedges |
| Tooling | Ubuntu's `dexdump` can't parse current hidden-API flags; there's no `lpunpack`/`lpmake` | Use the custom `dexnatives.py`, `lpunpack.py` and `lpmake.py` in `scripts/` |
| Privapp | `ro.control_privapp_permissions=enforce` | Copy mica's privapp-permission XMLs along with its apps |

## Next steps

Resume by verifying the VPD fix in QEMU, then get the Googlebook shell on screen, and only then start Duet hardware work.

**Resume checklist (QEMU):**

- [ ] Remount the source images read-only: `/mnt/gb/*`, `/mnt/emu/*` (plus the runtime APEX at `/mnt/emu/rt`), and `/mnt/cf/vendor`.
- [ ] Boot with `MEM=8192` and the `KEEP_META`/`KEEP_DATA` images. Check `getprop init.svc.vendor.google.desktop.vpd_executor.vpd-executor`.
- [ ] If the watchdog still fires, read the newest `/data/anr/*` for `waitForServiceNative` callers and grep logcat for "could not be found". Fix or drop each blocking service.
- [ ] Get SystemUITitan and NexusLauncher to render, then take a `screendump`.
- [ ] Measure idle RAM. Re-test with `MEM=4096` to see whether it fits the Duet's 4 GB.
- [ ] Optional: copy the three mica-only system apps (GameControlsInputProcessorService, IppPrintService, Protips).

**Duet bring-up (after QEMU works):**

1. **Kernel:** start from the ChromeOS or postmarketOS MT8183 kernel. Enable Android options (binderfs, ashmem/memfd, dm-verity off, erofs and ext4), plus the panfrost, mt8183 display, Wi-Fi (ath10k SDIO) and audio drivers.
2. **Vendor:**
   - Start from the emulator vendor with the ranchu/goldfish-only pieces removed.
   - Graphics: Mesa Panfrost for GLES, SwiftShader as the fallback, and drm\_hwcomposer or ranchu HWC3 in client mode on mediatek-drm.
   - Add real HALs for Wi-Fi, audio, power and input (the keyboard dock).
3. **Boot:** depthcharge in developer mode. Sign the kernel and ramdisk with `vbutil_kernel` dev keys, put it on a ChromeOS KERN partition on USB, and boot it with Ctrl+U.
4. **Storage:** the same single-disk super layout on USB first, then eMMC once it's stable.
5. **Expect:** slow graphics and a tight 4 GB. Plan zram tuning and trimming of the preinstalled Google apps.

## Sources

- [skylartaylor/gbos-vm](https://github.com/skylartaylor/gbos-vm): Googlebook on QEMU/Apple Silicon. It's the model for the Cuttlefish vendor and image tooling.
- [bangprovn/googlebookos-tb710fu](https://github.com/bangprovn/googlebookos-tb710fu): ARM tablet port that reuses the tablet's native vendor.
- [danbyumagic/gbrunch](https://github.com/danbyumagic/gbrunch): x86 port. Its REPORT.md documents the recovery catalog.
- [Google recovery catalog](https://dl.google.com/dl/edgedl/device/recovery/production_recovery.json): lists all five Googlebook images.
- [Android Desktop system-image catalog](https://dl.google.com/android/repository/sys-img/android-desktop/sys-img2-3.xml): lists the API 37.1 arm64 image.
- [AOSP test keys](https://android.googlesource.com/platform/build/+/refs/heads/main/target/product/security/): platform, testkey, shared, media, networkstack.
