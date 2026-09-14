/* =============================================================================
 *  冒烟固件用启动文件 —— 通用 Cortex-M，不绑定任何具体芯片。
 *
 *  刻意不写 .cpu / .fpu：这两项由工具链文件按 mcu.json 生成的
 *  -mcpu= / -mfpu= 参数决定，写死反而会和别的芯片冲突。
 *
 *  整个文件里__没有任何厂商代码__，所以可以放心放进模板仓库。
 * ========================================================================== */

    .syntax unified
    .thumb

    .global g_pfnVectors
    .global Reset_Handler
    .global Default_Handler

/* -----------------------------------------------------------------------------
 *  向量表：必须落在 FLASH 最前面（链接脚本用 KEEP(*(.isr_vector)) 保证不被裁剪）
 * -------------------------------------------------------------------------- */
    .section .isr_vector,"a",%progbits
    .type g_pfnVectors, %object
g_pfnVectors:
    .word _estack
    .word Reset_Handler
    .word Default_Handler       /* NMI */
    .word Default_Handler       /* HardFault */
    .word Default_Handler       /* MemManage */
    .word Default_Handler       /* BusFault */
    .word Default_Handler       /* UsageFault */
    .word 0
    .word 0
    .word 0
    .word 0
    .word Default_Handler       /* SVC */
    .word Default_Handler       /* DebugMon */
    .word 0
    .word Default_Handler       /* PendSV */
    .word Default_Handler       /* SysTick */
    .size g_pfnVectors, .-g_pfnVectors

/* -----------------------------------------------------------------------------
 *  复位入口：搬运 .data、清零 .bss，然后进 main
 * -------------------------------------------------------------------------- */
    .section .text.Reset_Handler
    .type Reset_Handler, %function
Reset_Handler:
    ldr r0, =_sdata
    ldr r1, =_edata
    ldr r2, =_sidata
    movs r3, #0
    b 2f
1:
    ldr r4, [r2, r3]
    str r4, [r0, r3]
    adds r3, r3, #4
2:
    adds r4, r0, r3
    cmp r4, r1
    bcc 1b

    ldr r2, =_sbss
    ldr r4, =_ebss
    movs r3, #0
    b 4f
3:
    str r3, [r2]
    adds r2, r2, #4
4:
    cmp r2, r4
    bcc 3b

    bl main
5:
    b 5b
    .size Reset_Handler, .-Reset_Handler

/* -----------------------------------------------------------------------------
 *  兜底中断处理：所有未实现的中断都停在这里。
 *  真实工程里应当换成自己的 handler（或直接看 SCB->CFSR 定位故障）。
 * -------------------------------------------------------------------------- */
    .section .text.Default_Handler,"ax",%progbits
    .type Default_Handler, %function
Default_Handler:
    b .
    .size Default_Handler, .-Default_Handler
