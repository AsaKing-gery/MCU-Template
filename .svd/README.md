# .svd 目录

把芯片的 SVD 文件放这里，文件名要与 `mcu.json` 里的 `svd` 字段一致。

- STM32 全系列 SVD：https://github.com/cmsis-svd/cmsis-svd-data （`data/ST/`）
- 或者安装 CMSIS Pack 后从 `<pack>/CMSIS/SVD/` 复制

SVD 文件用于调试时在 **XPERIPHERALS** 面板里查看外设寄存器。
没有 SVD 也能调试，只是看不到寄存器视图。

> 本目录已在 `.gitignore` 中忽略了 `*.svd`，避免把厂商大文件提交进仓库。
