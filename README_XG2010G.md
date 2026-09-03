# SPDX-License-Identifier: GPL-2.0+

# XG2010G U-Boot 说明

本仓库基于上游 U-Boot，加入 XG2010G 的 Airoha AN7581 类平台板级配置。
本地 `make` 产物仍只是 U-Boot/BL33 候选；GitHub Actions 会使用
Trusted Boot Key 自动生成可验证的 signed FIP 和 2 MiB `/dev/mtd0`
镜像。

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

BL2/BL31 有用，而且是当前可启动方案的关键输入：BL2 负责早期硬件和 DDR
初始化，BL31 负责 EL3 运行时环境。U-Boot 不会生成 BL2/BL31；除非拿到
Airoha 匹配平台的 TF-A/DDR 初始化源码和完整签名配置，否则不能“新生成”
等价 BL2/BL31。当前仓库内置了从
`original-device-backup-20260816/mtd0-bootloader-stock.bin` 提取的最小启动
输入：

| 文件 | 说明 | SHA256 |
| --- | --- | --- |
| `board/airoha/xg2010g/firmware/mtd0-prefix.bin` | mtd0 中 FIP 前的 `0x800` 字节前导区 | `82830140f4f8842702d0569065c27071b7cc24e0876e6c487cb4d9d81c294dd7` |
| `board/airoha/xg2010g/firmware/ubi-preloader.bin` | BL2/preloader | `6dfd08d05691cf2d89e0892b4e597a8d9a8ebab80a362c9b7a02868ffcddd1c8` |
| `board/airoha/xg2010g/firmware/bl31.bin` | BL31/EL3 runtime firmware | `e79bb6960e71384a4f8b67be0d0cd0f64042b174b4e6b2502428238f548245f3` |

这些内置文件只适用于匹配的 XG2010G 硬件、NAND 和 DDR 配置。完整原厂备份、
私钥、未公开签名配置、MAC/序列号和校准数据仍不得提交到公开仓库。

## GitHub Actions 构建 signed mtd0

`.github/workflows/build-mtd0.yml` 在 GitHub Actions 上强制执行签名构建；
不再提供 `skip`/未签名选项，也不会上传未签名 artifact。流程如下：

1. 编译 `configs/xg2010g_defconfig`，得到新的 `u-boot.bin`，作为 BL33。
2. 构建 ARM Trusted Firmware-A 的 `fiptool` 和 `cert_create`。
3. 默认使用仓库内置的 BL2、BL31 和 mtd0 前导区；也可用 Secret/私有 URL 覆盖。
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

使用仓库内置 BL2/BL31/prefix 时，只需要设置 Trusted Boot 私钥 Secret：

```console
gh secret set XG2010G_TB_PRIVATE_KEY --repo naoki66/u-boot-xg2010g < private_key.pem
```

如需覆盖内置输入，可提供完整原厂 mtd0 的私有 URL，让 Actions 自动截取
`0x800` 前导区并用 `fiptool unpack` 提取 BL2/BL31：

```console
gh secret set XG2010G_ORIGINAL_MTD0_URL --repo naoki66/u-boot-xg2010g --body "https://private.example/original-mtd0.bin"
gh variable set XG2010G_ORIGINAL_MTD0_SHA256 --repo naoki66/u-boot-xg2010g --body "<sha256>"
```

也可以分别提供 `XG2010G_BL2_B64`、`XG2010G_BL31_B64` 和
`XG2010G_MTD0_PREFIX_B64`，或对应的 `*_URL` Secret/Variable。由于 GitHub
Secret 有大小限制，BL2/BL31 或完整 mtd0 通常更适合放在私有对象存储、私有
Release Asset 或其它受控下载源，并用 SHA256 变量锁定内容。

如果 Trusted Boot 私钥曾经出现在聊天、日志、工单或公开位置，应视为已经
泄露，建议立即轮换，并只把新私钥写入 `XG2010G_TB_PRIVATE_KEY` Secret。

每次 Actions 构建都必须完成签名，否则 workflow 失败且不上传 artifact。
签名成功的 artifact 包含以下文件：

| 文件 | 用途 |
| --- | --- |
| `...-mtd0-signed.bin` | 完整 2 MiB `/dev/mtd0` bootloader 镜像，包含前导区、BL2、BL31、证书和 U-Boot/BL33 |
| `...-fip-signed.bin` | 放入 mtd0 `0x800` 偏移的完整 signed FIP |
| `...-ubi-preloader.bin` | BL2/preloader 裸文件，用于 X 模式第一段 XMODEM |
| `...-ubi-bl31-uboot.fip` | BL31 + U-Boot/BL33 FIP，用于 X 模式第二段 XMODEM |
| `...-bl31.bin` | BL31 裸文件，便于核对和离线调试 |
| `...-u-boot-raw.bin` | 本仓库本次编译出的 U-Boot/BL33 裸文件 |
| `sha256sums.txt` | 所有产物的 SHA256 校验值 |

artifact 内也保留不带版本号的 `ubi-preloader.bin`、`ubi-bl31-uboot.fip`、
`bl31.bin` 和 `u-boot-raw.bin`，方便救砖时直接选择文件。

## 证书产物

签名过程中会临时生成 `trusted_key.crt`、`tb_fw.crt`、`tb_fw_key.crt`、
`soc_fw.crt`、`soc_fw_key.crt`、`nt_fw.crt` 和 `nt_fw_key.crt`。这些是
TF-A `cert_create` 生成的 X.509 证书链/内容证书，用来把 BL2、BL31、
U-Boot/BL33 的哈希、公钥关系和 NV counter 等元数据写入 signed FIP。

这些 `.crt` 不是私钥，也不应包含 `XG2010G_TB_PRIVATE_KEY` 的私钥内容；
但单独的 `.crt` 文件会暴露证书链结构、公钥材料、镜像哈希和构建元数据，对
最终刷机也不是必需文件。signed FIP/mtd0 内部仍会包含启动验证必需的证书内容，
这是 Trusted Boot 启动链的一部分。因此 workflow 只在签名过程中临时生成单独
`.crt` 文件，不上传到 workflow artifact，也不上传到 GitHub Releases。

## TTL/TFTP 刷入 mtd0

该流程适用于已经能进原厂 U-Boot/TTL 命令行，并且当前 bootloader 提供
Airoha `flash` 命令的情况。电脑网线连接 1G 口，电脑 IP 设置为
`192.168.0.205/24`，U-Boot 侧设备 IP 使用 `192.168.0.1`。待刷文件必须是
Release 中完整 2 MiB 的 `...-mtd0-signed.bin`。

推荐电脑运行 TFTP server，U-Boot 主动拉取文件：

```console
setenv ipaddr 192.168.0.1
setenv serverip 192.168.0.205
setenv loadaddr 0x81800000
tftpboot ${loadaddr} xg2010g-...-mtd0-signed.bin
echo ${filesize}
crc32 ${loadaddr} ${filesize}
```

确认 `filesize` 为 `200000` 或 `0x200000` 后，只擦写 mtd0 的 2 MiB：

```console
flash erase 0x000000 0x200000
flash write 0x000000 0x200000 0x81800000
reset
```

原厂/Airoha `flash` 参数顺序是 `flash erase [addr] [len]` 和
`flash write [dst] [len] *[src]`。因此写入 mtd0 时，目的地址是
`0x000000`，长度是 `0x200000`，来源内存地址是 `0x81800000`。不要使用
`0x2000000`，那是 32 MiB，会覆盖 mtd0 后面的分区。

如果当前 bootloader 处在 TFTP receive/server 模式，电脑侧可能需要执行：

```console
tftp -i 192.168.0.1 put image.ub
```

这种情况下也应发送同一个 signed mtd0 产物；`image.ub` 只能作为传输文件名
示例，不能把系统镜像 `image.ub` 当 bootloader 写入 mtd0。

## X 模式救砖

如果 mtd0 写坏导致 NAND 不能正常启动，Airoha BootROM 通常仍可进入
串口 X 模式加载临时引导。该流程需要 TTL 串口和支持 XMODEM 的终端工具。

首次使用救砖链时，可能需要先加载一次 `bootext.ram`：

1. 断电。
2. 按住 `RESET` 键，同时通电启动。
3. 终端显示 `CCCC` 时表示设备已进入 X 模式。
4. 在终端菜单中选择“文件 -> 传输 -> XMODEM -> 发送”。
5. 选择 `bootext.ram`，等待传输完成。之后通常不再需要重复加载该文件。

正式刷机步骤如下：

1. **TTL 进入救砖模式**：断电后按住 `RESET` 键，同时通电启动；按 `X`/`x`，
   终端显示 `CCCC` 后进入 XMODEM 接收。
2. **传输 BL2/preloader**：选择“文件 -> 传输 -> XMODEM -> 发送”，发送
   Actions 产物中的 `...-ubi-preloader.bin` 或 `ubi-preloader.bin`。
   传输完成后设备会自动重启。
3. **再次进入 X 模式**：重新断电，按住 `RESET` 后通电；提示
   `Press x to load BL31 + U-Boot FIP` 时输入 `x`。
4. **传输 BL31 + U-Boot FIP**：再次选择“文件 -> 传输 -> XMODEM -> 发送”，
   发送 `...-ubi-bl31-uboot.fip` 或 `ubi-bl31-uboot.fip`。
5. **关键时序**：第二段 XMODEM 进度到 100% 前提前按住 `RESET`，等待设备灯
   完成闪烁并进入流水式闪烁后再松开。
6. 浏览器使用无痕模式访问 `http://192.168.1.1/uboot.html`。
7. 选择 `ubi-squashfs-sysupgrade.itb`；`BL2` 选择
   `...-ubi-preloader.bin`，`U-Boot` 选择 `...-ubi-bl31-uboot.fip`。
8. 必须勾选“先重建 UBI”，等待数分钟完成刷写。
9. 刷写完成后务必断电重启设备。

注意：`bootext.ram` 属于平台救援链文件，不由本仓库的 U-Boot 编译生成；
需要保留已验证可用的原厂/平台版本。

## 正常引导系统

Web Recovery 刷写 `ubi-squashfs-sysupgrade.itb` 并勾选“先重建 UBI”后，正常
启动应直接断电重启，不再按 `RESET`，让 U-Boot 按默认环境启动系统。

如果需要恢复原厂/legacy `tclinux` 引导环境，可在 TTL 中断后参考以下命令。
这些命令会写入 `uenv`，请先确认当前环境已备份：

```console
setenv bootflag 0
setenv one flash read 0x602100 0x4000000 $loadaddr
setenv two "; bootm"
setenv bootcmd "$one$two"
setenv one
setenv two
setenv bootargs 'sdram_conf=0x00108893 vendor_name=ECONET Technologies Corp. product_name=xPON ONU ubi.mtd=system ethaddr=00:AA:BB:01:23:40 snmp_sysobjid=1.2.3.4.5 country_code=ff ether_gpio=0c power_gpio=1515 dsl_gpio=0b internet_gpio=02 multi_upgrade_gpio=0b020400000000000000000000000000 onu_type=61 qdma_init=69bb root=/dev/mtdblock4 ro console=ttyS0,115200n8 earlycon bootflag=0 serdes_sel=0 serdes_pon=000 serdes_ethernet=411 serdes_wifi1=005 serdes_wifi2=413 serdes_usb1=111 serdes_usb2=000 tclinux_info=0x1fc4d8b,0x5724,0x36101e,0x366840,0x3000000,0x0,0x2000,0x0,0x2000,0x0'
setenv serdes_ethernet 411
saveenv
reset
```

`serdes_ethernet=411` 是光口/PON 方向，上网 2.5G 正常；`421` 是网口方向，
已知场景下 2.5G 网口不能用于上网，不建议作为默认值。

如果系统已经启动到 OpenWrt/failsafe，需要清理 overlay 或重新设置密码，可用：

```console
rm -rf /overlay
mount_root
passwd
reboot
```

## 构建

推荐在 WSL/Linux 文件系统中构建，或用 `git archive` 导出临时构建副本，
以避免 Windows drvfs 挂载上的脚本可执行位和符号链接问题：

```console
make CROSS_COMPILE=aarch64-linux-gnu- xg2010g_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

构建出的 `u-boot.bin` 只是 BL33 候选文件。更多细节见
`doc/board/airoha/xg2010g.rst`。
