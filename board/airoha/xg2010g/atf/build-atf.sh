#!/usr/bin/env bash
set -euo pipefail

: "${ATF_DIR:?}"
: "${MBEDTLS_DIR:?}"
: "${ARM32_CROSS_COMPILE:?}"
: "${AARCH64_CROSS_COMPILE:?}"
: "${LZMA:?}"
: "${OUTPUT_DIR:?}"

script_dir=$(cd "$(dirname "$0")" && pwd)
jobs=${JOBS:-$(nproc)}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/bl2.bin" "$OUTPUT_DIR/bl31.bin"

common_flags=(
    PLAT=en7523
    MBEDTLS_DIR="$MBEDTLS_DIR"
    CONFIG_ECNT=1
    TCSUPPORT_OPENWRT=1
    TCSUPPORT_ATF_UNOPEN=0
    TCSUPPORT_CPU_EN7581=1
    TCSUPPORT_CPU_EN7523=1
    TCSUPPORT_CPU_ARMV8=1
    TCSUPPORT_UBOOT_64BIT=1
    TCSUPPORT_EMMC=1
    TCSUPPORT_UBOOT=1
    TCSUPPORT_BL2_OPTIMIZATION=1
    # 第二阶段 FIP 使用 1 MiB 接收区，解压工作区从其末端开始。
    TCSUPPORT_TCBOOT_1MB_SIZE=1
    CFLAGS=-DECNT_NAND_FIP_IN_BOOT_PARTITION
    TOOLS_DIR="$(dirname "$LZMA")"
)

make -C "$ATF_DIR" PLAT=en7523 clean

build_bl2_stage() {
    local stage=$1
    local output=$2

    make -C "$ATF_DIR" -j"$jobs" \
        "${common_flags[@]}" \
        ARCH=aarch32 \
        CROSS_COMPILE="$AARCH64_CROSS_COMPILE" \
        ARM32TOOLCHAIN_BASE="$ARM32_CROSS_COMPILE" \
        "$stage=1" bl2
    cp "$ATF_DIR/$output" "$work_dir/$output"
    make -C "$ATF_DIR" PLAT=en7523 clean
}

build_bl2_stage IMAGE_BL21 bl21.bin
build_bl2_stage IMAGE_BL22 bl22.lzma
build_bl2_stage IMAGE_BL23 bl23.lzma

cc \
    -DFLASH_TABLE_OPEN \
    -DTCSUPPORT_BL2_OPTIMIZATION \
    -I"$ATF_DIR/plat/ecnt/en7523/include" \
    -o "$work_dir/spi_nand_flash_table" \
    "$ATF_DIR/plat/ecnt/common/drivers/flash/spi_nand_flash_table.c"
(
    cd "$work_dir"
    ./spi_nand_flash_table
)
"$LZMA" e "$work_dir/flash_table.bin" "$work_dir/flash_table.lzma"

python3 "$script_dir/pack-bl2.py" \
    --bl21 "$work_dir/bl21.bin" \
    --bl22 "$work_dir/bl22.lzma" \
    --bl23 "$work_dir/bl23.lzma" \
    --flash-table "$work_dir/flash_table.lzma" \
    --output "$OUTPUT_DIR/bl2.bin"

make -C "$ATF_DIR" -j"$jobs" \
    "${common_flags[@]}" \
    ARCH=aarch64 \
    CROSS_COMPILE="$AARCH64_CROSS_COMPILE" \
    bl31
"$LZMA" e "$ATF_DIR/build/en7523/release/bl31.bin" "$OUTPUT_DIR/bl31.bin"
