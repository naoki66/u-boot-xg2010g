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

## GitHub Actions 构建 signed mtd0

本仓库新增 `.github/workflows/build-mtd0.yml`，用于在 GitHub Actions 上
完成以下流程：

1. 编译 `configs/xg2010g_defconfig`，得到新的 `u-boot.bin`，作为 BL33。
2. 构建 ARM Trusted Firmware-A 的 `fiptool` 和 `cert_create`。
3. 从私有输入恢复原厂 BL2、BL31 和 mtd0 前导区，或从原厂 mtd0 中提取。
4. 使用 Trusted Boot 私钥重新生成从 BL2 开始的证书链。
5. 组装 signed FIP，并把它放入 2 MiB 的 `mtd0-bootloader-xg2010g-signed.bin`。

默认边界保持不变：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `XG2010G_MTD0_SIZE` | `0x200000` | 仅覆盖 mtd0/bootloader 的 2 MiB |
| `XG2010G_FIP_OFFSET` | `0x800` | 原厂 mtd0 中 FIP 起始偏移 |
| `XG2010G_FIP_ALIGN` | `0x400` | FIP payload 对齐，匹配已观察到的原厂偏移 |
| `XG2010G_TFA_REF` | `v2.13.0` | 用于构建通用 `fiptool`/`cert_create` 的 TF-A 版本 |

可先设置非敏感仓库变量：

```console
gh variable set XG2010G_MTD0_SIZE --repo naoki66/u-boot-xg2010g --body 0x200000
gh variable set XG2010G_FIP_OFFSET --repo naoki66/u-boot-xg2010g --body 0x800
gh variable set XG2010G_FIP_ALIGN --repo naoki66/u-boot-xg2010g --body 0x400
gh variable set XG2010G_TFA_REF --repo naoki66/u-boot-xg2010g --body v2.13.0
```

私钥、原厂 mtd0、BL2、BL31 和 mtd0 前导区只能通过 GitHub Secrets 或私有
下载地址提供，不能提交到仓库。推荐输入方式是提供完整原厂 mtd0 的私有
URL，让 Actions 自动截取 `0x800` 前导区并用 `fiptool unpack` 提取 BL2/BL31：

```console
gh secret set XG2010G_TB_PRIVATE_KEY --repo naoki66/u-boot-xg2010g < private_key.pem
gh secret set XG2010G_ORIGINAL_MTD0_URL --repo naoki66/u-boot-xg2010g --body "https://private.example/original-mtd0.bin"
gh variable set XG2010G_ORIGINAL_MTD0_SHA256 --repo naoki66/u-boot-xg2010g --body "<sha256>"
```

也可以分别提供 `XG2010G_BL2_B64`、`XG2010G_BL31_B64` 和
`XG2010G_MTD0_PREFIX_B64`，或对应的 `*_URL` Secret/Variable。由于 GitHub
Secret 有大小限制，BL2/BL31 或完整 mtd0 通常更适合放在私有对象存储、私有
Release Asset 或其它受控下载源，并用 SHA256 变量锁定内容。

如果 Trusted Boot 私钥曾经出现在聊天、日志、工单或公开位置，应视为已经
泄露，建议立即轮换，并只把新私钥写入 `XG2010G_TB_PRIVATE_KEY` Secret。

## 构建

推荐在 WSL/Linux 文件系统中构建，或用 `git archive` 导出临时构建副本，
以避免 Windows drvfs 挂载上的脚本可执行位和符号链接问题：

```console
make CROSS_COMPILE=aarch64-linux-gnu- xg2010g_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

构建出的 `u-boot.bin` 只是 BL33 候选文件。更多细节见
`doc/board/airoha/xg2010g.rst`。
