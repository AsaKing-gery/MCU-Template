---
name: Bug 报告
about: 构建失败 / 调试异常 / 模板本身有问题？按这个填，能少来回好几轮
title: '[Bug] '
labels: bug
assignees: ''
---

<!--
提交之前先看一眼这几条，很多问题能自己解决：

  * 构建失败        -> 先跑 tools/check/ci.ps1，它的报错信息比 CMake 原始输出完整
  * 中文乱码        -> 跑 tools/format/fix-encoding.ps1（clangd 只认 UTF-8）
  * 补全/跳转失效   -> 跑 tools/check/check-includes.ps1 看有没有循环包含
  * 找不到头文件    -> 确认 tools/env/setup-env.ps1 跑过，并且 VSCode 重启过
  * 链接报 undefined reference -> 多半是缺 CubeMX 生成的 syscalls.c
-->

## 现象

一句话说清楚发生了什么。（"编译不过"太笼统，说清是 configure / 编译 / 链接 哪一步）

## 复现步骤

1.
2.
3.

**实际结果**

**期望结果**

## 环境

| 项 | 值 |
|---|---|
| 芯片型号（`mcu.json` 的 `device`） | |
| 工程来源 | [ ] 模板新建 &nbsp; [ ] CubeMX 工程套模板 &nbsp; [ ] 模板仓库本身 |
| 操作系统 | [ ] Windows 10 &nbsp; [ ] Windows 11 &nbsp; [ ] Linux &nbsp; [ ] macOS |
| `arm-none-eabi-gcc --version` | |
| `cmake --version` / `ninja --version` | |
| VSCode 扩展版本 | clangd: <br>CMake Tools: <br>Cortex-Debug: |

## 完整报错

```
（贴原文，不要截图 —— 截图没法搜索，也没法复制）
（终端里的中文乱码也一起贴，那是编码信息，有用）
```

## 你改过下面这些文件吗

- [ ] `mcu.json`
- [ ] `CMakeLists.txt`
- [ ] `tools/` 下的脚本
- [ ] `.vscode/` 下的配置
- [ ] 都没改过（纯开箱状态就出问题）

## 补充

还有其它线索吗？（换过编译器版本、改过 `.format-exclude`、板子上的实际表现……）
