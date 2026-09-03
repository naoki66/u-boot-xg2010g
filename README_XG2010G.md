# XG2010G U-Boot 说明

本仓库基于上游 U-Boot，加入 XG2010G 的 Airoha AN7581 类平台板级配置。
当前产物是新的 U-Boot/BL33 候选，不是已经完成 Trusted Boot 签名、
可直接写入 `/dev/mtd0` 的完整 FIP。

## 当前 NAND 布局

目标设备按 512 MiB SLC NAND 规划：

| 分区 | 起始 | 结束（不含） | 大小 | 说明 |
| --- | --- | --- | --- | --- |
| `bootloader` | `0x00000000` | `0x00200000` | 2 MiB | 完整启动镜像/FIP，只读保护 |
| `uenv` | `0x00200000` | `0x00400000` | 2 MiB | U-Boot 环境 |
| `dsd` | `0x00400000` | `0x00600000` | 2 MiB | 保留原厂数据 |
| `ubi` | `0x00600000` | `0x1be00000` | 440 MiB | 后续系统镜像/UBI 数据 |
| `reserved_bmt` | `0x1be00000` | `0x20000000` | 66 MiB | NAND 坏块替代/BMT 预留，只读保护 |

系统升级只应刷写 `ubi` 分区，也就是偏移 `0x00600000`、长度
`0x1b800000` 的区域。不要覆盖 `bootloader`、`uenv`、`dsd` 或
`reserved_bmt`。

## BL2、BL31 与 FIP

Airoha 平台的 `/dev/mtd0` 通常不是裸 `u-boot.bin`，而是包含 BL2、BL31、
BL33/U-Boot 以及证书材料的 FIP。普通 U-Boot 构建不会生成 BL2/BL31。

首个兼容方案应保留与本机硬件匹配的原厂 BL2/BL31，将本仓库编译出的
`u-boot.bin` 作为 BL33，再使用匹配平台的 `fiptool`、UUID、装载地址、
对齐规则和 Trusted Boot 签名流程重新组装 FIP。若设备启用锁定的
Trusted Boot，没有设备认可的签名根，新 FIP 可能无法通过 BootROM 或 BL2
校验。

原厂备份、提取出的 BL2/BL31、FIP、私钥、证书、签名配置、MAC/序列号和
校准数据不得提交到公开仓库。

## 构建

推荐在 WSL/Linux 文件系统中构建，或用 `git archive` 导出临时构建副本，
以避免 Windows drvfs 挂载上的脚本可执行位和符号链接问题：

```console
make CROSS_COMPILE=aarch64-linux-gnu- xg2010g_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

构建出的 `u-boot.bin` 只是 BL33 候选文件。更多细节见
`doc/board/airoha/xg2010g.rst`。
