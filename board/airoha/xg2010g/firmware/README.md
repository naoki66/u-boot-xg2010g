# XG2010G mtd0 prefix

`mtd0-prefix.bin` contains the first `0x800` bytes extracted from the XG2010G
stock `mtd0` backup dated 2026-08-16. GitHub Actions preserves it before the
new signed FIP.

BL2 and BL31 are built from the pinned Airoha TF-A source by
`board/airoha/xg2010g/atf/build-atf.sh`.

| File | Role | Size | SHA256 |
| --- | --- | ---: | --- |
| `mtd0-prefix.bin` | First `0x800` bytes before the FIP in `mtd0` | 2,048 | `82830140f4f8842702d0569065c27071b7cc24e0876e6c487cb4d9d81c294dd7` |

This prefix belongs to the analyzed Airoha AN7581-class XG2010G mtd0 layout.
