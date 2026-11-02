#!/bin/bash
# graft.sh: stage system/system_ext/product = emulator base + mica Googlebook layer, re-signed with AOSP test keys.
set -euo pipefail
ROOT=$HOME/gbos-duet; B=$ROOT/build; S=$B/stage; K=$ROOT/keys; MSE=/mnt/gb/system_ext_a; MP=/mnt/gb/product_a
# AOSP public test keys (platform/testkey/shared/media); networkstack is deliberately NOT re-signed
mkdir -p $K; for k in platform shared media testkey; do for e in pk8 x509.pem; do [ -s $K/$k.$e ] || \
  curl -fsSL "https://android.googlesource.com/platform/build/+/refs/heads/main/target/product/security/$k.$e?format=TEXT" | base64 -d > $K/$k.$e; done; done
cd $B; sudo rm -rf $S/system $S/system_ext $S/product
echo "== copy bases"
sudo cp -a /mnt/emu/system $S/system
sudo cp -a /mnt/emu/system_ext $S/system_ext
sudo cp -a $MP $S/product
# product: keep emulator SELinux policy (mica's is compiled against a different plat policy)
sudo rm -rf $S/product/etc/selinux; sudo cp -a /mnt/emu/product/etc/selinux $S/product/etc/selinux
echo "== system_ext: swap AOSP shell for Googlebook shell"
for a in SystemUI Launcher3QuickStep Settings GoogleSdkSetup; do sudo rm -rf $S/system_ext/priv-app/$a; done
for a in SystemUITitan SettingsGoogle NexusLauncherRelease SetupWizardDesktopPrebuilt_cl3b ChromePrewarm FauResetPreferences \
         RepairMode-Desktop SystemUIClocks-BigNum SystemUIClocks-Calligraphy SystemUIClocks-Growth SystemUIClocks-Inflate \
         SystemUIClocks-Metro SystemUIClocks-NumOverlap SystemUIClocks-Weather WallpaperPickerGoogleRelease YourWidgetsStub \
         com.android.desktop.serviceability dcf snapshotservice; do sudo cp -a $MSE/priv-app/$a $S/system_ext/priv-app/; done
for a in DesktopRepairModeResources DisplayCaptureService PersistentBackgroundServices-desktop PowerOffAlarm; do sudo cp -a $MSE/app/$a $S/system_ext/app/; done
sudo mkdir -p $S/system_ext/overlay; sudo cp -a $MSE/overlay/. $S/system_ext/overlay/
for d in permissions sysconfig default-permissions; do
  [ -d $MSE/etc/$d ] || continue; sudo mkdir -p $S/system_ext/etc/$d
  for f in $MSE/etc/$d/*; do case $(basename $f) in *qti*|*qualcomm*|*qcom*|*ims*|*cne*) continue;; esac; sudo cp -a $f $S/system_ext/etc/$d/; done
done
echo "== re-sign build-key APKs with AOSP test keys"
declare -A MAP=([301aa3cb08113450]=platform [a4ed98934a2e64a7]=platform [6cecc50e34ae31bf]=testkey [d7756fd7771f570a]=testkey
                [6e433e476ed0789c]=shared [781d7764dd7b9d35]=media)
sudo find $S/system $S/system_ext $S/product -name '*.apk' > $B/apks.txt
export K; for c in "${!MAP[@]}"; do echo "$c ${MAP[$c]}"; done > $B/keymap.txt
cat > $B/resign1.sh <<'EOS'
#!/bin/bash
f="$1"; c=$(apksigner verify --print-certs "$f" 2>/dev/null | grep -m1 'SHA-256' | awk '{print substr($NF,1,16)}')
k=$(awk -v c="$c" '$1==c{print $2}' @ROOT@/build/keymap.txt); [ -n "$k" ] || exit 0
t=$(mktemp); apksigner sign --key @ROOT@/keys/$k.pk8 --cert @ROOT@/keys/$k.x509.pem --in "$f" --out "$t" \
  && cat "$t" > "$f" && echo "$k $(basename $f)" || echo "FAIL $f"; rm -f "$t" "$t.idsig"
EOS
sed -i "s#@ROOT@#$ROOT#g" $B/resign1.sh; chmod +x $B/resign1.sh; sudo xargs -P8 -I{} $B/resign1.sh {} < $B/apks.txt > $B/resign.log
awk '{print $1}' $B/resign.log | sort | uniq -c
echo "== SELinux mac_permissions: emulator platform cert -> AOSP test platform cert"
NEW=$(openssl x509 -in $K/platform.x509.pem -outform DER | xxd -p | tr -d '\n')
for f in $(sudo grep -rl 'signer signature' $S/system/system/etc/selinux $S/system_ext/etc/selinux $S/product/etc/selinux /dev/null 2>/dev/null); do
  sudo python3 -I - "$f" "$NEW" <<'EOP'
import re,sys
p,new=sys.argv[1],sys.argv[2]; x=open(p).read()
# the @PLATFORM signer is the one with seinfo value="platform"
m=re.search(r'<signer signature="([0-9a-fA-F]+)"\s*>\s*<seinfo value="platform"',x)
if m: x=x.replace(m.group(1),new); open(p,'w').write(x); print('patched',p)
EOP
done
