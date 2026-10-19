#ifndef C_FFN_DRIVER_H
#define C_FFN_DRIVER_H
#include <stdint.h>
#ifndef FFN_ROWS
#define FFN_ROWS 99
#endif
#ifndef FFN_COLS
#define FFN_COLS 256
#endif
#define FFN_CSR_BASE 0x11000000u
#define FFN_X_BASE   0xa0000000u
#define FFN_W_BASE   0xa0004000u
#define FFN_B_BASE   0xa000c000u
#define FFN_Y_BASE   0xa0010000u
enum { FFN_CONTROL=0x00, FFN_STATUS=0x04, FFN_LAYER=0x08, FFN_SHIFT=0x0c,
       FFN_X=0x10, FFN_W=0x14, FFN_B=0x18, FFN_Y=0x1c,
       FFN_OUTPUTS=0x20, FFN_CYCLES=0x24, FFN_ERROR=0x28, FFN_VERSION=0x2c };
/* X/W/Y: packed little-endian signed16. Bias: sign-extended signed40 in 8 bytes.
 * Addresses refer to shared SRAM; loading uses the platform loader interface.
 * Returns 0, -1(busy), -2(timeout), -3(hardware error), -4(bad arguments).
 * A timeout does not abort hardware: caller must wait or reset the whole fabric.
 */
int ffn_run(unsigned layer, unsigned shift, uint32_t x, uint32_t w,
            uint32_t b, uint32_t y, uint32_t max_polls, uint32_t *cycles);
static inline void ffn_fence(void) {
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}
static inline uint32_t ffn_read(unsigned offset) {
    return *(volatile uint32_t *)(uintptr_t)(FFN_CSR_BASE+offset);
}
static inline void ffn_write(unsigned offset,uint32_t value) {
    *(volatile uint32_t *)(uintptr_t)(FFN_CSR_BASE+offset)=value;
}
#endif
