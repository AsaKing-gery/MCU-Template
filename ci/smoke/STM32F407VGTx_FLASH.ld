/* =============================================================================
 *  冒烟固件用链接脚本 —— 最小可用的 Cortex-M 布局。
 *
 *  名字必须和模板 mcu.json 里的 "linkerScript" 完全一致（当前是
 *  STM32F407VGTx_FLASH.ld），因为工具链文件是拿这个名字去
 *  工程根 / Core/ / ld/ / LinkerScript/ 里 find_file 的
 *  ——见 cmake/gcc-arm-none-eabi.cmake 第 4 节。
 *
 *  真实工程请直接用 CubeMX 生成的 .ld，不要用这一份。
 * ========================================================================== */
ENTRY(Reset_Handler)

_estack = ORIGIN(RAM) + LENGTH(RAM);

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
  RAM   (xrw) : ORIGIN = 0x20000000, LENGTH = 128K
}

SECTIONS
{
  /* 向量表必须钉在 FLASH 起始处 */
  .isr_vector :
  {
    . = ALIGN(4);
    KEEP(*(.isr_vector))
    . = ALIGN(4);
  } >FLASH

  .text :
  {
    . = ALIGN(4);
    *(.text)
    *(.text*)
    *(.glue_7)
    *(.glue_7t)
    *(.eh_frame)

    KEEP(*(.init))
    KEEP(*(.fini))

    . = ALIGN(4);
    _etext = .;
  } >FLASH

  .rodata :
  {
    . = ALIGN(4);
    *(.rodata)
    *(.rodata*)
    . = ALIGN(4);
  } >FLASH

  /* .data 的初始值存在 FLASH，运行时由 Reset_Handler 搬到 RAM */
  _sidata = LOADADDR(.data);

  .data :
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data)
    *(.data*)
    . = ALIGN(4);
    _edata = .;
  } >RAM AT> FLASH

  .bss :
  {
    . = ALIGN(4);
    _sbss = .;
    __bss_start__ = _sbss;
    *(.bss)
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
    __bss_end__ = _ebss;
  } >RAM

  . = ALIGN(4);
  _end = .;
  __end__ = .;
  PROVIDE(end = .);
}
