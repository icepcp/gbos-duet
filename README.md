# Googlebook OS on the Lenovo Chromebook Duet

Research and build scripts for running Google's Googlebook OS (Android 17 desktop) on the
Lenovo Chromebook Duet (`krane`, MediaTek MT8183, Cortex-A73/A53, 4 GB).

**Status: paused, not bootable on the Duet yet.** The CPU blocker is solved, and the real Googlebook
system_server boots most of the way under QEMU. See [`notes/FINDINGS.md`](notes/FINDINGS.md) for the full log.

## The problem and the trick

- The ARM Googlebook images (Dell `mica`, HP `quartz`) are compiled for **Cortex-A55 / ARMv8.2**.
  LSE atomics and `ldapr` are inlined everywhere, including `linker64`, libc, libutils and libbinder.
  The Duet's cores are **ARMv8.0**, so every process would SIGILL.
- Google's Android Studio **"Google APIs Desktop" arm64 image (API 37.1)** is the same Android release,
  built for generic ARMv8.0.
- The JNI boundary matches: all 5,195 native methods the emulator's libraries register exist, with
  identical signatures, in mica's Java framework (`notes/jni/`).
- So the build is a **hybrid**:
  - **Native layer:** the emulator's (ARMv8.0).
  - **Java layer:** Googlebook's (`services.jar`, `desktop-services.jar`, framework-res, apps,
    overlays). Java runs on any CPU.

## Pipeline

Run on an ARM64 Linux box (developed on Ubuntu 22.04, Neoverse-N1, no KVM). The project is
expected at `~/gbos-duet`.

1. **Download** (about 20 GB) into `dl/`:
   - [Dell mica recovery 16471258](https://dl.google.com/device/recovery/mica-user/16471258/recovery.zip)
     (sha256 `cb68dd6d…a645d7`)
   - [Emulator Desktop API 37.1 arm64](https://dl.google.com/android/repository/sys-img/android-desktop/arm64-v8a-37.1_r01.zip)
   - [Cuttlefish arm64 16373615](https://ci.android.com/builds/submitted/16373615/aosp_cf_arm64_only_phone-userdebug/latest/aosp_cf_arm64_only_phone-img-16373615.zip)
     (sha256 `051caf80…c85c18`; the page hands out a short-lived link)
2. **Extract and mount read-only:**
   - Unpack the zips. Unsparse Cuttlefish `super.img` with `simg2img`.
   - Split each super partition with `scripts/lpunpack.py <disk> <super byte offset> <outdir>`.
   - Loop-mount (EROFS) at these paths:

   | Mount | Contents |
   | --- | --- |
   | `/mnt/gb/{system_a,system_ext_a,product_a,vendor_a}` | mica partitions |
   | `/mnt/emu/{system,system_ext,product,vendor}` | emulator partitions |
   | `/mnt/emu/rt` | emulator `com.android.runtime` APEX payload |
   | `/mnt/cf/vk` | payload of Cuttlefish vendor `com.google.cf.vulkan.apex` |

3. **Build** with the scripts in `scripts/`:

   | Step | Script | What it does |
   | --- | --- | --- |
   | 1 | `vendor.sh` | Emulator vendor + SwiftShader, guest-render props, fstab by-name, no sensors HAL, adb networking, Googlebook VPD HAL |
   | 2 | `graft.sh` | Emulator system/system_ext + mica product + Googlebook shell apps; re-sign with AOSP test keys |
   | 3 | `hybrid.sh` | Mica Java framework and classpaths onto the emulator native layer; drop ARMv8.2 preopt |
   | 4 | `rebuild.sh` | Pack ext4 partitions; `lpmake.py` builds super; `build_qemu_disk.sh` builds one GPT disk + initrd |
   | 5 | `run_qemu.sh` | QEMU `virt`, `-cpu cortex-a72` (ARMv8.0, Duet-equivalent ISA); `MEM=8192` |

4. **Inspect** the running guest:
   - `python3 scripts/gsh.py '<cmd>' 200` runs a root shell over the serial console.
   - `adb connect 127.0.0.1:5555` works once networking is up.
   - `scripts/poll_boot.sh` waits for SystemUI, `boot_completed` or a fatal error.
   - Screenshots come from the QEMU monitor (`build/out/mon.sock`, `screendump`).

**Analysis tools:**

- `isa_scan.sh`, `unguarded.sh`, `isa_funcs.sh`: find ARMv8.1+ instructions not behind an outline-atomics guard.
- `notes/jni/dexnatives.py`: list native methods from modern dex files (Ubuntu's `dexdump` can't parse them).
- `cpio_list.py`: unpack concatenated ramdisk cpio archives.

## Where it stopped

`DesktopRepairModeService` waits forever for `vendor.google.desktop.vpd_executor.IVpdExecutor/default`,
so the system_server watchdog fires. `vendor.sh` adds mica's VPD HAL, but whether that fixes it is
unverified. After that come the Googlebook shell on screen, measuring RAM against 4 GB, and the Duet
bring-up itself: kernel, Panfrost vendor, and a depthcharge USB boot.

## References

- [skylartaylor/gbos-vm](https://github.com/skylartaylor/gbos-vm): Googlebook in QEMU on Apple Silicon
- [bangprovn/googlebookos-tb710fu](https://github.com/bangprovn/googlebookos-tb710fu): ARM tablet port
- [danbyumagic/gbrunch](https://github.com/danbyumagic/gbrunch): x86 port and recovery-catalog notes

No Google, Dell or HP binaries are included. Everything is downloaded from Google's own servers at build time.
