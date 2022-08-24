#!/usr/bin/env bash
#
# Copyright (C) 2022 Kneba <abenkenary3@gmail.com>
#

# Main
MainPath="$(pwd)"
MainClangPath="${MainPath}/clang"
MainClangZipPath="${MainPath}/clang-zip"
ClangPath="${MainClangZipPath}"
GCCaPath="${MainPath}/GCC64"
GCCbPath="${MainPath}/GCC32"
MainZipGCCaPath="${MainPath}/GCC64-zip"
MainZipGCCbPath="${MainPath}/GCC32-zip"

# Identity
KERNELNAME=TheOneMemory
VERSION=SL
VARIANT=EAS

# Clone Kernel Source
git clone --depth=1 https://$USERNAME:$TOKEN@github.com/strongreasons/kernel_asus_sdm660 -b eas-12 $DEVICE_CODENAME

# Clone AOSP Clang
ClangPath=${MainClangZipPath}
[[ "$(pwd)" != "${MainPath}" ]] && cd "${MainPath}"
mkdir $ClangPath
rm -rf $ClangPath/*
wget -q  https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r458507.tar.gz -O "clang-r458507.tar.gz"
tar -xf clang-r458507.tar.gz -C $ClangPath

# Clone GCC
mkdir $GCCaPath
mkdir $GCCbPath
wget -q https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r16.tar.gz -O "gcc64.tar.gz"
tar -xf gcc64.tar.gz -C $GCCaPath
wget -q https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r16.tar.gz -O "gcc32.tar.gz"
tar -xf gcc32.tar.gz -C $GCCbPath

# Prepare
KERNEL_ROOTDIR=$(pwd)/$DEVICE_CODENAME # IMPORTANT ! Fill with your kernel source root directory.
export LD=ld.lld
export KBUILD_BUILD_USER=queen # Change with your own name or else.
IMAGE=$(pwd)/$DEVICE_CODENAME/out/arch/arm64/boot/Image.gz-dtb
CLANG_VER="$("$ClangPath"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
LLD_VER="$("$ClangPath"/bin/ld.lld --version | head -n 1)"
export KBUILD_COMPILER_STRING="$CLANG_VER with $LLD_VER"
DATE=$(date +"%F-%S")
START=$(date +"%s")

# Java
command -v java > /dev/null 2>&1

# Telegram
export BOT_MSG_URL="https://api.telegram.org/bot$TG_TOKEN/sendMessage"

# Telegram messaging
tg_post_msg() {
  curl -s -X POST "$BOT_MSG_URL" -d chat_id="$TG_CHAT_ID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=html" \
    -d text="$1"
}
# Compile
compile(){
cd ${KERNEL_ROOTDIR}
export HASH_HEAD=$(git rev-parse --short HEAD)
export COMMIT_HEAD=$(git log --oneline -1)
make -j$(nproc) O=out ARCH=arm64 $KERNEL_DEFCONFIG
make -j$(nproc) ARCH=arm64 O=out \
    LD_LIBRARY_PATH="${ClangPath}/lib64:${LD_LIBRARY_PATH}" \
    PATH=$ClangPath/bin:$GCCaPath/bin:$GCCbPath/bin:/usr/bin:${PATH} \
    CC=${ClangPath}/bin/clang \
    NM=${ClangPath}/bin/llvm-nm \
    CXX=${ClangPath}/bin/clang++ \
    AR=${ClangPath}/bin/llvm-ar \
    STRIP=${ClangPath}/bin/llvm-strip \
    OBJCOPY=${ClangPath}/bin/llvm-objcopy \
    OBJDUMP=${ClangPath}/bin/llvm-objdump \
    OBJSIZE=${ClangPath}/bin/llvm-size \
    READELF=${ClangPath}/bin/llvm-readelf \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    HOSTAR=${ClangPath}/bin/llvm-ar \
    HOSTCC=${ClangPath}/bin/clang \
    HOSTCXX=${ClangPath}/bin/clang++

   if ! [ -a "$IMAGE" ]; then
	finerr
	exit 1
   fi
   git clone $ANYKERNEL -b eas-12 AnyKernel
	cp $IMAGE AnyKernel
}
# Push kernel to telegram
function push() {
    cd AnyKernel
    curl -F document="@$ZIP_FINAL.zip" "https://api.telegram.org/bot$TG_TOKEN/sendDocument" \
        -F chat_id="$TG_CHAT_ID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=Markdown" \
        -F caption="🟢 Compile took $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) second(s). | For <b>$DEVICE_CODENAME</b> | <b>${KBUILD_COMPILER_STRING}</b>"
}
# Find Error
function finerr() {
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=markdown" \
        -d text="❌ I'm tired of compiling kernels,And I choose to give up...please give me motivation"
    exit 1
}
# Zipping
function zipping() {
    cd AnyKernel || exit 1
    zip -r9 $KERNELNAME-[$VERSION]-$VARIANT-"$DATE" . -x ".git*" -x "README.md" -x "*.zip"

    ZIP_FINAL="$KERNELNAME-[$VERSION]-$VARIANT-$DATE"

    msg "|| Signing Zip ||"
    tg_post_msg "<code>🔑 Signing Zip file with AOSP keys..</code>"

	curl -sLo zipsigner-4.0.jar https://github.com/baalajimaestro/AnyKernel3/raw/master/zipsigner-4.0.jar
	java -jar zipsigner-4.0.jar "$ZIP_FINAL".zip "$ZIP_FINAL"-signed.zip
	ZIP_FINAL="$ZIP_FINAL-signed"
    cd ..
}
compile
zipping
END=$(date +"%s")
DIFF=$(($END - $START))
push
