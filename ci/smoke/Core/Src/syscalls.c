/* =============================================================================
 *  冒烟固件用的 newlib 桩函数
 *
 *  模板默认 floatIo=true，CMakeLists.txt 会加
 *      -Wl,--undefined=_printf_float -Wl,--undefined=_scanf_float
 *  把 newlib-nano 里的浮点 printf/scanf 强行链进来。那套代码会引用
 *  _write / _sbrk / _exit 等系统调用，**必须由工程提供**，否则链接阶段报
 *  undefined reference（真实工程里这份文件由 CubeMX 生成）。
 *
 *  这里全部做成空实现：冒烟固件不接串口，输出直接丢弃即可。
 * ========================================================================== */
#include <errno.h>
#include <stddef.h>
#include <sys/stat.h>
#include <sys/types.h>

/* 由链接脚本提供 */
extern char _end;

void *_sbrk(ptrdiff_t incr)
{
	static char *heap_end = 0;
	char *prev_heap_end;

	if(heap_end == 0)
	{
		heap_end = &_end;
	}

	prev_heap_end = heap_end;
	heap_end += incr;

	return (void *)prev_heap_end;
}

int _write(int file, char *ptr, int len)
{
	(void)file;
	(void)ptr;
	return len;
}

int _read(int file, char *ptr, int len)
{
	(void)file;
	(void)ptr;
	(void)len;
	return 0;
}

int _close(int file)
{
	(void)file;
	return -1;
}

int _fstat(int file, struct stat *st)
{
	(void)file;
	st->st_mode = S_IFCHR;
	return 0;
}

int _isatty(int file)
{
	(void)file;
	return 1;
}

off_t _lseek(int file, off_t ptr, int dir)
{
	(void)file;
	(void)ptr;
	(void)dir;
	return 0;
}

void _exit(int status)
{
	(void)status;

	for(;;)
	{
	}
}

int _kill(int pid, int sig)
{
	(void)pid;
	(void)sig;
	errno = EINVAL;
	return -1;
}

int _getpid(void)
{
	return 1;
}
