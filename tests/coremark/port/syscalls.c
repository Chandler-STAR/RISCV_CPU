/* Newlib / picolibc syscall stubs + 魔法 UART 0xF000_0000
 *
 * picolibc 默认是 tinystdio 模式 —— 不走 _write，要通过
 *   FDEV_SETUP_STREAM 把 putc 绑到 FILE 结构里。
 * 同时保留 _write/_read/_sbrk 等 POSIX stub，以兼容 newlib 路线。
 */
#include <stdio.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <unistd.h>

#define MAGIC_UART ((volatile unsigned char *)0xF0000000)
#define MAGIC_EXIT ((volatile unsigned int  *)0xF0000004)

/* ---- 字符输出原语 ---- */
static int uart_putc(char c, FILE *file) {
    (void)file;
    *MAGIC_UART = (unsigned char)c;
    return (unsigned char)c;
}

/* ---- picolibc tinystdio：把 stdout/stdin/stderr 绑到 uart_putc ---- */
#ifdef FDEV_SETUP_STREAM
static FILE __stdio = FDEV_SETUP_STREAM(uart_putc, NULL, NULL, _FDEV_SETUP_WRITE);
FILE *const stdin  = &__stdio;
FILE *const stdout = &__stdio;
FILE *const stderr = &__stdio;
#endif

/* ---- newlib 风格 syscalls（picolibc tinystdio 不用，但留着不亏） ---- */
extern char _end[];
static char *heap_ptr = (char *)_end;

void *_sbrk(int incr) {
    char *prev = heap_ptr;
    heap_ptr += incr;
    return prev;
}

int _write(int fd, const void *buf, int len) {
    (void)fd;
    const unsigned char *p = (const unsigned char *)buf;
    for (int i = 0; i < len; i++) *MAGIC_UART = p[i];
    return len;
}

int _read(int fd, void *buf, int len)        { (void)fd; (void)buf; (void)len; return 0; }
int _close(int fd)                           { (void)fd; return -1; }
int _isatty(int fd)                          { (void)fd; return 1; }
int _lseek(int fd, int o, int w)             { (void)fd; (void)o; (void)w; return 0; }
int _fstat(int fd, struct stat *st)          { (void)fd; st->st_mode = S_IFCHR; return 0; }
int _kill(int pid, int sig)                  { (void)pid; (void)sig; errno = EINVAL; return -1; }
int _getpid(void)                            { return 1; }

void _exit(int code) {
    *MAGIC_EXIT = (unsigned int)code | 1u;
    while (1) { __asm__ volatile ("nop"); }
}
