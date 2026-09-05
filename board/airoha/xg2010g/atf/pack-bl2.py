#!/usr/bin/env python3

import argparse
import binascii
import struct
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pack the three-stage Airoha BL2 image")
    parser.add_argument("--bl21", type=Path, required=True)
    parser.add_argument("--bl22", type=Path, required=True)
    parser.add_argument("--bl23", type=Path, required=True)
    parser.add_argument("--flash-table", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    bl21 = args.bl21.read_bytes()
    bl22 = args.bl22.read_bytes()
    bl23 = args.bl23.read_bytes()
    flash_table = args.flash_table.read_bytes()

    if len(bl21) != 14336:
        raise SystemExit(f"unexpected BL21 size: {len(bl21)}")

    # BL21 从固定 SRAM 地址读取这组小端字段，并据此解压 BL22、BL23 和 NAND 表。
    header = struct.pack(
        "<9I",
        len(bl22),
        len(bl23),
        len(flash_table),
        0x1E843C00 + 36,
        0x08004000,
        len(bl22),
        0,
        0,
        0,
    )
    image = bl21 + header + bl22 + bl23 + flash_table
    crc = binascii.crc32(image) ^ 0xFFFFFFFF
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image + struct.pack("<I", crc))


if __name__ == "__main__":
    main()
