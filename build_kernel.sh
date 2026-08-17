#!/bin/bash

# Exit on any error
set -e

# ==========================================
# Argument Parsing
# ==========================================
if [ -z "$1" ]; then
    echo "[!] Error: No device specified."
    echo "Usage: $0 <device_name> [ksu] [miui|aosp]"
    echo "Example: $0 lmi"
    echo "         $0 lmi ksu"
    echo "         $0 lmi ksu miui"
    echo "         $0 lmi aosp"
    exit 1
fi

DEVICE_NAME="$1"
DEFCONFIG="${DEVICE_NAME}_defconfig"
DEFCONFIG_PATH="arch/arm64/configs/${DEFCONFIG}"

if [ ! -f "$DEFCONFIG_PATH" ]; then
    echo "[!] Error: Defconfig not found at $DEFCONFIG_PATH"
    echo "[!] Please verify the device name and try again."
    exit 1
fi

ENABLE_KSU=0
TARGET_OS="both"

shift
# Parse remaining arguments loosely
for arg in "$@"; do
    case "$arg" in
        ksu) ENABLE_KSU=1 ;;
        miui) TARGET_OS="miui" ;;
        aosp) TARGET_OS="aosp" ;;
    esac
done

# ==========================================
# Configuration & Environment
# ==========================================
KERNEL_DIR="$(pwd)"
TOOLCHAIN_BIN="$HOME/zyc-clang/bin"

export PATH="${TOOLCHAIN_BIN}:${PATH}"
export ARCH="arm64"
export SUBARCH="arm64"

# ccache Setup
export CCACHE_DIR="$HOME/.cache/ccache_mikernel"
export CCACHE_EXEC=$(command -v ccache)

if [ -z "$CCACHE_EXEC" ]; then
    echo "[!] ccache not found! Please install ccache first."
    exit 1
fi

export USE_CCACHE=1
export CROSS_COMPILE="aarch64-linux-gnu-"
export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"

echo "[*] Checking Clang version..."
clang --version || { echo "[!] Clang not found at ${TOOLCHAIN_BIN}. Please check the path."; exit 1; }

echo "[*] Setting up ccache in $CCACHE_DIR..."
mkdir -p "$CCACHE_DIR"

# ==========================================
# KernelSU Setup
# ==========================================
if [ "$ENABLE_KSU" -eq 1 ]; then
    echo "==========================================="
    echo " [*] Initializing KernelSU (ReSukiSU) Setup"
    echo "==========================================="
    echo "[*] Downloading and running ReSukiSU remote setup script..."
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash
    echo "[+] KernelSU setup finished."
fi

# ==========================================
# Baseband-guard Setup
# ==========================================
echo "==========================================="
echo " [*] Initializing Baseband-guard Setup"
echo "==========================================="
echo "[*] Downloading and running Baseband-guard remote setup script..."
wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash

echo "[*] Patching security/Kconfig for baseband_guard..."
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' security/Kconfig
echo "[+] Baseband-guard setup finished."
echo "==========================================="

# ==========================================
# AnyKernel3 Setup
# ==========================================
echo "==========================================="
echo " [*] Initializing AnyKernel3 Workspace"
echo "==========================================="
rm -rf anykernel
echo "[*] Cloning AnyKernel3..."
git clone https://github.com/AstideLabs/AnyKernel3 -b master --single-branch --depth=1 anykernel
echo "[+] AnyKernel3 cloned successfully."
echo "==========================================="

# ==========================================
# Modular Build Function
# ==========================================
build_target() {
    local OS_TYPE=$1
    echo "==========================================="
    echo " Starting Kernel Compilation for ${DEVICE_NAME} (Target: $OS_TYPE)"
    echo "==========================================="
    
    local OUT_DIR="${KERNEL_DIR}/out_${OS_TYPE}"
    
    local MAKE_OPTS=(
        -j"$(nproc)"
        O="${OUT_DIR}"
        ARCH="${ARCH}"
        SUBARCH="${SUBARCH}"
        LLVM=1
        LLVM_IAS=1
        CC="ccache clang"
        HOSTCC="ccache clang"
        CROSS_COMPILE="${CROSS_COMPILE}"
        CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"
    )

    echo "[*] Cleaning ${OUT_DIR}..."
    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"

    local DTS_SOURCE="arch/arm64/boot/dts/vendor/qcom"
    local DTS_BACKUP=".dts.bak.${OS_TYPE}"

    if [ "$OS_TYPE" == "miui" ]; then
        echo "[*] Applying MIUI DTS patches..."
        cp -a "${DTS_SOURCE}" "${DTS_BACKUP}"
        
        # Apply MIUI specific sed patches to dts
        sed -i 's/<154>/<1537>/g' ${DTS_SOURCE}/dsi-panel-j1s* || true
        sed -i 's/<154>/<1537>/g' ${DTS_SOURCE}/dsi-panel-j2* || true
        sed -i 's/<155>/<1544>/g' ${DTS_SOURCE}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi || true
        sed -i 's/<155>/<1545>/g' ${DTS_SOURCE}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi || true
        sed -i 's/<155>/<1546>/g' ${DTS_SOURCE}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<155>/<1546>/g' ${DTS_SOURCE}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<70>/<695>/g' ${DTS_SOURCE}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi || true
        sed -i 's/<71>/<710>/g' ${DTS_SOURCE}/dsi-panel-j1s* || true
        sed -i 's/<71>/<710>/g' ${DTS_SOURCE}/dsi-panel-j2* || true

        sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' ${DTS_SOURCE}/dsi-panel* || true
        sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' ${DTS_SOURCE}/dsi-panel* || true
        sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' ${DTS_SOURCE}/dsi-panel* || true
        sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' ${DTS_SOURCE}/dsi-panel* || true

        sed -i 's/120 90 60/120 90 60 50 30/g' ${DTS_SOURCE}/dsi-panel-g7a-36-02-0c-dsc-video.dtsi || true
        sed -i 's/120 90 60/120 90 60 50 30/g' ${DTS_SOURCE}/dsi-panel-g7a-37-02-0a-dsc-video.dtsi || true
        sed -i 's/120 90 60/120 90 60 50 30/g' ${DTS_SOURCE}/dsi-panel-g7a-37-02-0b-dsc-video.dtsi || true
        sed -i 's/144 120 90 60/144 120 90 60 50 48 30/g' ${DTS_SOURCE}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi || true

        sed -i 's/\/\/39 00 00 00 00 00 03 51 03 FF/39 00 00 00 00 00 03 51 03 FF/g' ${DTS_SOURCE}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi || true
        sed -i 's/\/\/39 00 00 00 00 00 03 51 0D FF/39 00 00 00 00 00 03 51 0D FF/g' ${DTS_SOURCE}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${DTS_SOURCE}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${DTS_SOURCE}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${DTS_SOURCE}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${DTS_SOURCE}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${DTS_SOURCE}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${DTS_SOURCE}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${DTS_SOURCE}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${DTS_SOURCE}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${DTS_SOURCE}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${DTS_SOURCE}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${DTS_SOURCE}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${DTS_SOURCE}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${DTS_SOURCE}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${DTS_SOURCE}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${DTS_SOURCE}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${DTS_SOURCE}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${DTS_SOURCE}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${DTS_SOURCE}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${DTS_SOURCE}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 01 00 03 51 03 FF/39 01 00 00 01 00 03 51 03 FF/g' ${DTS_SOURCE}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi || true
        sed -i 's/\/\/39 01 00 00 11 00 03 51 03 FF/39 01 00 00 11 00 03 51 03 FF/g' ${DTS_SOURCE}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi || true
    fi

    echo "[*] Making defconfig: ${DEFCONFIG}..."
    make "${MAKE_OPTS[@]}" "${DEFCONFIG}"

    # ----------------------------------------------------
    # Configuration tweaks
    # ----------------------------------------------------
    
    # 1. Baseband-guard configuration (Always applied)
    echo "[*] Injecting Baseband-guard configuration..."
    scripts/config --file "${OUT_DIR}/.config" -e BBG

    # 2. KernelSU configurations (syscall hook, not inline)
    if [ "$ENABLE_KSU" -eq 1 ]; then
        echo "[*] Injecting KernelSU configurations (syscall hook)..."
        scripts/config --file "${OUT_DIR}/.config" \
            -e KSU \
            -e THREAD_INFO_IN_TASK
    fi

    # 3. MIUI configurations
    if [ "$OS_TYPE" == "miui" ]; then
        echo "[*] Injecting MIUI specific configurations..."
        scripts/config --file "${OUT_DIR}/.config" \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
            -e PERF_CRITICAL_RT_TASK \
            -e SF_BINDER \
            -e OVERLAY_FS \
            -e MIGT \
            -e MIGT_ENERGY_MODEL \
            -e MIHW \
            -e PACKAGE_RUNTIME_INFO \
            -e BINDER_OPT \
            -e KPERFEVENTS \
            -e MILLET \
            -e PERF_HUMANTASK \
            -d LTO_CLANG \
            -e LTO_NONE \
            -d SHADOW_CALL_STACK \
            -e XIAOMI_MIUI \
            -d MI_MEMORY_SYSFS \
            -e TASK_DELAY_ACCT \
            -e MIUI_ZRAM_MEMORY_TRACKING \
            -e PERF_HELPER \
            -e BOOTUP_RECLAIM \
            -e MI_RECLAIM \
            -e RTMM \
            -d REKERNEL \
            -d REKERNEL_NETWORK
    fi

    # 4. AOSP configurations
    if [ "$OS_TYPE" == "aosp" ]; then
        echo "[*] Injecting AOSP specific configurations..."
        scripts/config --file "${OUT_DIR}/.config" \
            -e REKERNEL \
            -e REKERNEL_NETWORK
    fi

    # We always need to re-evaluate dependencies because BBG is injected unconditionally
    echo "[*] Updating config (make olddefconfig)..."
    make "${MAKE_OPTS[@]}" olddefconfig

    # 5. DroidSpaces container support — merge dedicated config fragment
    #    (must run after olddefconfig to avoid being reset by BBG/KSU/MIUI injections)
    echo "[*] Merging DroidSpaces container support config..."
    cp "${KERNEL_DIR}/droidspaces.config" arch/arm64/configs/droidspaces.config
    ./scripts/kconfig/merge_config.sh -O "${OUT_DIR}" -m "${OUT_DIR}/.config" arch/arm64/configs/droidspaces.config
    echo "[*] DroidSpaces config lines in .config after merge:"
    grep -E '^(# )?CONFIG_(SYSCTL|SYSVIPC|POSIX_MQUEUE|PID_NS|DEVTMPFS|CGROUP_PIDS|CGROUP_DEVICE|ANDROID_PARANOID_NETWORK|BRIDGE_NETFILTER|NF_TABLES|CHECKPOINT_RESTORE|SCHED_AUTOGROUP)[ =]' "${OUT_DIR}/.config" || true
    make "${MAKE_OPTS[@]}" olddefconfig
    echo "[*] DroidSpaces config lines in .config after olddefconfig:"
    grep -E '^(# )?CONFIG_(SYSCTL|SYSVIPC|POSIX_MQUEUE|PID_NS|DEVTMPFS|CGROUP_PIDS|CGROUP_DEVICE|ANDROID_PARANOID_NETWORK|BRIDGE_NETFILTER|NF_TABLES|CHECKPOINT_RESTORE|SCHED_AUTOGROUP)[ =]' "${OUT_DIR}/.config" || true
    # hard fail if SYSVIPC or PID_NS did not survive
    grep -q '^CONFIG_SYSVIPC=y' "${OUT_DIR}/.config" || { echo "FATAL: CONFIG_SYSVIPC did not survive merge"; grep -n 'SYSVIPC' "${OUT_DIR}/.config" | head -5; exit 1; }
    grep -q '^CONFIG_PID_NS=y' "${OUT_DIR}/.config" || { echo "FATAL: CONFIG_PID_NS did not survive merge"; grep -n 'PID_NS' "${OUT_DIR}/.config" | head -5; exit 1; }
    # ANDROID_PARANOID_NETWORK is NOT a valid symbol in this tree (removed by Xiaomi);
    # kconfig discards it during olddefconfig. Informative only, do not hard-fail.
    grep -q '^CONFIG_ANDROID_PARANOID_NETWORK=n' "${OUT_DIR}/.config" \
        && echo "[i] CONFIG_ANDROID_PARANOID_NETWORK=n survived (kernel supports it)" \
        || echo "[i] CONFIG_ANDROID_PARANOID_NETWORK dropped by olddefconfig (symbol missing in tree, expected)"

    # 6. Apply DroidSpaces cocci patches
    if command -v spatch &>/dev/null; then
        if [ -f "net/netfilter/xt_qtaguid.c" ]; then
            spatch --sp-file "${KERNEL_DIR}/fix_kernel_panic_in_xt_qtaguid.cocci" --in-place net/netfilter/xt_qtaguid.c 2>/dev/null || true
            echo "[*] Applied xt_qtaguid cocci fix"
        fi
        if [ -f "kernel/cgroup/cgroup.c" ] && ! grep -q "kernfs_create_link" "kernel/cgroup/cgroup.c"; then
            spatch --sp-file "${KERNEL_DIR}/fix_restore_cgroup_file_prefix_handling.cocci" --in-place kernel/cgroup/cgroup.c 2>/dev/null || true
            echo "[*] Applied cgroup cocci fix"
        elif [ -f "kernel/cgroup.c" ] && ! grep -q "kernfs_create_link" "kernel/cgroup.c"; then
            spatch --sp-file "${KERNEL_DIR}/fix_restore_cgroup_file_prefix_handling.cocci" --in-place kernel/cgroup.c 2>/dev/null || true
            echo "[*] Applied cgroup cocci fix"
        else
            echo "[-] cgroup.c already patched or not found, skipping"
        fi
    else
        echo "[-] spatch not found, skipping cocci patches"
    fi

    # ----------------------------------------------------
    # Compilation
    # ----------------------------------------------------
    echo "[*] Building kernel..."
    make "${MAKE_OPTS[@]}" 

    # Restore DTS backup for MIUI
    if [ "$OS_TYPE" == "miui" ]; then
        echo "[*] Restoring DTS backups..."
        rm -rf "${DTS_SOURCE}"
        mv "${DTS_BACKUP}" "${DTS_SOURCE}"
    fi

    echo "==========================================="
    if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        echo "[+] $OS_TYPE Build Successful!"
        echo "[+] Kernel Image path: ${OUT_DIR}/arch/arm64/boot/Image"
        
        echo "[*] Generating dtb..."
        find "${OUT_DIR}/arch/arm64/boot/dts" -name '*.dtb' -exec cat {} + > "${OUT_DIR}/arch/arm64/boot/dtb"

        echo "[*] Packaging to AnyKernel3 ($OS_TYPE)..."
        # 确保独立打包：清空现有的 kernels 目录
        rm -rf anykernel/kernels/*
        mkdir -p "anykernel/kernels/${OS_TYPE}/"
        
        cp "${OUT_DIR}/arch/arm64/boot/Image" "anykernel/kernels/${OS_TYPE}/"
        cp "${OUT_DIR}/arch/arm64/boot/dtb" "anykernel/kernels/${OS_TYPE}/"
        
        if [ -f "${OUT_DIR}/arch/arm64/boot/dtbo.img" ]; then
            cp "${OUT_DIR}/arch/arm64/boot/dtbo.img" "anykernel/kernels/${OS_TYPE}/"
        fi
        
        # 确定 ZIP 文件名
        local KSU_ZIP_STR="NoKernelSU"
        if [ "$ENABLE_KSU" -eq 1 ]; then
            KSU_ZIP_STR="ReSukiSU-SuSFS"
        fi
        local GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
        local OS_UPPER=$(echo "$OS_TYPE" | tr '[:lower:]' '[:upper:]')
        local ZIP_FILENAME="APTKernel_${OS_UPPER}_${DEVICE_NAME}_${KSU_ZIP_STR}_Droidspaces_$(date +'%Y%m%d_%H%M%S')_anykernel3_${GIT_COMMIT_ID}.zip"
        
        echo "[*] Zipping $ZIP_FILENAME ..."
        pushd anykernel > /dev/null
        zip -r9 "$ZIP_FILENAME" ./* -x .git .gitignore out/ ./*.zip > /dev/null
        mv "$ZIP_FILENAME" ../
        popd > /dev/null
        
        echo "[+] $OS_TYPE kernel binaries successfully packed into: $ZIP_FILENAME"
    else
        echo "[-] $OS_TYPE Build Failed. Kernel Image not found."
        exit 1
    fi
}

# ==========================================
# Execute builds based on target OS
# ==========================================
if [ "$TARGET_OS" == "aosp" ] || [ "$TARGET_OS" == "both" ]; then
    build_target "aosp"
fi

if [ "$TARGET_OS" == "miui" ] || [ "$TARGET_OS" == "both" ]; then
    build_target "miui"
fi

echo "==========================================="
echo "[*] ccache stats:"
ccache -s
echo "[+] All requested builds completed!"
