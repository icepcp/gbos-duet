#!/bin/bash
# hybrid.sh: on top of graft.sh's stage/system, install mica's Java framework layer (ISA-neutral) over emu native layer.
set -euo pipefail
S=~/gbos-duet/build/stage/system/system; M=/mnt/gb/system_a/system; K=~/gbos-duet/keys
# 1. framework jars + framework-res from mica; drop ALL preopt (mica's is cortex-a55 code, emu's mismatches new jars)
sudo rm -rf $S/framework; sudo mkdir -p $S/framework
for f in $(sudo ls $M/framework); do case $f in arm64|arm|oat|*.vdex|*.vdex.fsv_meta|*.oat|*.art|*.prof) ;; *) sudo cp -a $M/framework/$f $S/framework/;; esac; done
sudo find $S/framework -name '*.fsv_meta' -delete
# 2. classpath config from mica (adds desktop-services.jar, GameControlsInputProcessorLib.jar)
sudo cp -a $M/etc/classpaths/. $S/etc/classpaths/
# 3. app/priv-app preopt compiled against old boot classpath -> remove so ART re-verifies/JITs
sudo find $S/app $S/priv-app -type d -name oat -prune -exec rm -rf {} +
# 4. mica-only JNI / Rust deps (never overwrite emu native libs)
for l in libdesktop_power_jni.so libjni.dylib.so libsimd_cesu8.dylib.so libsimdutf8.dylib.so libcombine.dylib.so; do
  [ -e $S/lib64/$l ] || { sudo test -e $M/lib64/$l && sudo cp -a $M/lib64/$l $S/lib64/ && echo "added $l"; } ; done
# 5. mica platform permission/feature XMLs that emu lacks
for d in permissions sysconfig; do for f in $(sudo ls $M/etc/$d); do sudo test -e $S/etc/$d/$f || { sudo cp -a $M/etc/$d/$f $S/etc/$d/ && echo "added etc/$d/$f"; }; done; done
# 6. re-sign framework-res with AOSP test platform key
t=$(mktemp); sudo apksigner sign --key $K/platform.pk8 --cert $K/platform.x509.pem --in $S/framework/framework-res.apk --out $t && sudo cp $t $S/framework/framework-res.apk; rm -f $t $t.idsig
sudo ls $S/framework | wc -l
