MEMORY
{
  rom (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
  prog (rx) : ORIGIN = 0x00010000, LENGTH = 480K
  ram (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}

MPU_MIN_ALIGN = 8K;
PAGE_SIZE = 4K;

INCLUDE ../kernel_layout.ld
