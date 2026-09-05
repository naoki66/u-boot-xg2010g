#!/usr/bin/env python3

import argparse
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise SystemExit(f"unexpected source content: {path}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare Airoha TF-A for XG2010G")
    parser.add_argument("source", type=Path)
    args = parser.parse_args()

    replace_once(
        args.source / "plat/ecnt/en7523/ecnt_io_storage.c",
        """\tpolicies[FIP_IMAGE_ID] = &fip_memmap_policy;

#if defined(IMAGE_BL23)
\t/* Expect UBI if we are on NAND AND we are not in recovery procedure */
""",
        """\tpolicies[FIP_IMAGE_ID] = &fip_memmap_policy;

/*
 * XG2010G 的 NAND 启动和 XMODEM 救援都会把第二阶段 FIP 放入
 * PLAT_ECNT_FIP_BASE，BL23 因此沿用 memmap 策略读取 BL31 与 BL33。
 */
#if defined(IMAGE_BL23) && !defined(ECNT_NAND_FIP_IN_BOOT_PARTITION)
\t/* Expect UBI if we are on NAND AND we are not in recovery procedure */
""",
    )
    replace_once(
        args.source / "plat/ecnt/common/drivers/flash/spi_nand_flash_table.c",
        """\tint buf_size = 1000000; //16M
\tstruct bl2_flash_H flash_h;
\tchar *buf = NULL;
""",
        """\tint buf_size = 1000000; //16M
\tstruct bl2_flash_H flash_h = {0};
\tchar *buf = NULL;
""",
    )


if __name__ == "__main__":
    main()
