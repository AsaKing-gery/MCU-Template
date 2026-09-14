/* =============================================================================
 *  CI 冒烟测试固件 —— 只为验证模板的构建链路，不属于任何真实工程。
 *
 *  为什么需要它：
 *    MCU-Template 仓库本身是「骨架」，只有 App/Src/app.c 这一个空壳，
 *    既没有链接脚本，也没有 newlib 的系统调用桩。所以直接
 *    cmake configure/build 会红在**链接阶段**：
 *
 *        -- linker script : MCU_LDSCRIPT_FILE-NOTFOUND
 *        undefined reference to `_getpid'
 *        undefined reference to `_fstat'
 *        undefined reference to `_isatty'
 *        collect2: error: ld returned 1 exit status
 *
 *    原因：模板 mcu.json 里 floatIo=true，CMakeLists.txt 会加
 *    -Wl,--undefined=_printf_float -Wl,--undefined=_scanf_float
 *    把 newlib-nano 的 stdio 体系强行链进来，于是 _write/_sbrk/_fstat
 *    这些桩必须由工程提供（真实工程里由 CubeMX 生成的 syscalls.c 负责）。
 *    ——这就是模板仓库 CI 一直失败的真实原因。
 *
 *    解法不是「关掉 CI」，而是给它一份**零 HAL 依赖**的最小固件：
 *    配合同目录下的 syscalls.c / startup_smoke.s 和仓库根的
 *    STM32F407VGTx_FLASH.ld，就能完整跑通模板的整条管道：
 *
 *        mcu.json 解析 → 架构编译参数(-mcpu/-mfpu/-mfloat-abi)
 *        → 源文件收集(递归收集 .c 与 .s) → 头文件目录探测 → 编译
 *        → -T 链接脚本链接 → objcopy 生成 .hex/.bin → 彩色体积报告
 *
 *    也就是说，这个固件验证的是「模板的管道还通不通」，而不是业务逻辑。
 * ========================================================================== */
#include <stdint.h>

/* 变量刻意散布在各个段里，顺带检验链接脚本的段布局与 .data 搬运是否正确 */
const uint32_t g_smoke_const = 0xA5A5A5A5u;
const uint8_t g_smoke_blob[16] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15};
uint32_t g_smoke_data = 0x12345678u;
uint32_t g_smoke_bss;
volatile uint32_t g_smoke_loops;

static void smoke_spin(volatile uint32_t loops)
{
	while(loops-- != 0u)
	{
		g_smoke_loops++;
	}
}

int main(void)
{
	g_smoke_bss = g_smoke_const ^ g_smoke_data;

	for(;;)
	{
		g_smoke_data += g_smoke_blob[g_smoke_data & 0x0Fu];
		smoke_spin(1000u);
	}
}
