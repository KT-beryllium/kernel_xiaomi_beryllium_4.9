#!/usr/bin/env bash
# Build script for kernel_xiaomi_beryllium (sdm845) – Clang + GCC 4.9 binutils
# ============================================================================

set -e

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
KERNEL_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="${KERNEL_DIR}/../tools"

CLANG_DIR="${TOOLS_DIR}/clang"
GCC_64_DIR="${TOOLS_DIR}/gcc64"
GCC_32_DIR="${TOOLS_DIR}/gcc32"

OUT_DIR="${KERNEL_DIR}/out"

# ---------------------------------------------------------------------------
# Toolchain sources
# ---------------------------------------------------------------------------
CLANG_SOURCE="https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git"
CLANG_BRANCH="lineage-20.0"

GCC_GNU=false   # use LLVM binutils (llvm-ar, llvm-nm, etc.) instead of GNU
GCC_64_SOURCE="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9.git"
GCC_64_BRANCH="android12L-release"
GCC_32_SOURCE="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9.git"
GCC_32_BRANCH="android12L-release"

# ---------------------------------------------------------------------------
# Kernel config
# ---------------------------------------------------------------------------
ARCH="arm64"
SUBARCH="arm64"
DEFCONFIG="beryllium_user_defconfig"

JOBS=$(nproc --all)

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[  OK]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERR ]${RESET}  $*"; }

# ---------------------------------------------------------------------------
# Clone helpers
# ---------------------------------------------------------------------------
clone_if_missing() {
    local name="$1" url="$2" branch="$3" dest="$4"
    if [[ -d "${dest}/.git" ]]; then
        log_info "${name} already present at ${dest}, skipping clone."
    else
        log_info "Cloning ${name} (branch: ${branch}) …"
        git clone --depth=1 --single-branch -b "${branch}" "${url}" "${dest}"
        log_ok "${name} cloned."
    fi
}

# ---------------------------------------------------------------------------
# Step 1 – Fetch toolchains
# ---------------------------------------------------------------------------
fetch_toolchains() {
    mkdir -p "${TOOLS_DIR}"
    clone_if_missing "Clang"  "${CLANG_SOURCE}"  "${CLANG_BRANCH}"  "${CLANG_DIR}"
    clone_if_missing "GCC64"  "${GCC_64_SOURCE}" "${GCC_64_BRANCH}" "${GCC_64_DIR}"
    clone_if_missing "GCC32"  "${GCC_32_SOURCE}" "${GCC_32_BRANCH}" "${GCC_32_DIR}"
}

# ---------------------------------------------------------------------------
# Step 2 – Build environment
# ---------------------------------------------------------------------------
setup_env() {
    CLANG_BIN="${CLANG_DIR}/bin"
    GCC_64_BIN="${GCC_64_DIR}/bin"
    GCC_32_BIN="${GCC_32_DIR}/bin"

    export PATH="${CLANG_BIN}:${GCC_64_BIN}:${GCC_32_BIN}:${PATH}"

    # Verify clang is reachable
    if ! command -v clang &>/dev/null; then
        log_error "clang not found in PATH after toolchain setup. Aborting."
        exit 1
    fi
    log_ok "Clang: $(clang --version | head -1)"

    CLANG_TRIPLE="aarch64-linux-gnu-"
    CROSS_COMPILE="${GCC_64_BIN}/aarch64-linux-android-"
    CROSS_COMPILE_ARM32="${GCC_32_BIN}/arm-linux-androideabi-"

    # When GCC_GNU=false use LLVM integrated binutils
    if [[ "${GCC_GNU}" == "false" ]]; then
        LLVM_FLAGS="LLVM=1 LLVM_IAS=1"
    else
        LLVM_FLAGS=""
    fi
}

# ---------------------------------------------------------------------------
# Step 3 – Make wrapper
# ---------------------------------------------------------------------------
kmake() {
    make -C "${KERNEL_DIR}" \
        O="${OUT_DIR}" \
        ARCH="${ARCH}" \
        SUBARCH="${SUBARCH}" \
        CC="clang" \
        CLANG_TRIPLE="${CLANG_TRIPLE}" \
        CROSS_COMPILE="${CROSS_COMPILE}" \
        CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
        HOSTCFLAGS="-fcommon" \
        KCFLAGS="-fno-builtin-sprintf" \
        ${LLVM_FLAGS} \
        -j"${JOBS}" \
        "$@"
}

# ---------------------------------------------------------------------------
# Step 4 – Build
# ---------------------------------------------------------------------------
build_kernel() {
    log_info "Setting up output directory: ${OUT_DIR}"
    mkdir -p "${OUT_DIR}"

    log_info "Generating config from ${DEFCONFIG} …"
    kmake "${DEFCONFIG}"

    log_info "Building kernel (${JOBS} threads) …"
    kmake

    # Locate Image.gz-dtb
    local image
    image=$(find "${OUT_DIR}/arch/${ARCH}/boot" -maxdepth 1 \
            -name "Image.gz-dtb" -o -name "Image.gz" -o -name "Image" 2>/dev/null | head -1)

    if [[ -z "${image}" ]]; then
        log_error "Kernel image not found in ${OUT_DIR}/arch/${ARCH}/boot"
        exit 1
    fi

    log_ok "Build complete!"
    log_ok "Kernel image: ${image}"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    echo -e "${BOLD}======================================${RESET}"
    echo -e "${BOLD}  Beryllium Kernel Build Script${RESET}"
    echo -e "${BOLD}======================================${RESET}"

    fetch_toolchains
    setup_env
    build_kernel
}

main "$@"
