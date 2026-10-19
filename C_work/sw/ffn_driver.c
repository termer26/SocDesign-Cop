#include "ffn_driver.h"

static int in_sram(uint32_t address, uint32_t bytes, uint32_t alignment) {
    return address>=0xa0000000u && address<=0xa0080000u-bytes &&
           (address & (alignment-1u))==0;
}

int ffn_run(unsigned layer, unsigned shift, uint32_t x, uint32_t w,
            uint32_t b, uint32_t y, uint32_t max_polls, uint32_t *cycles) {
    if (layer>=12 || shift>63 || !max_polls ||
        !in_sram(x,FFN_ROWS*64u*2u,2) || !in_sram(w,64u*FFN_COLS*2u,2) ||
        !in_sram(b,FFN_COLS*8u,8) || !in_sram(y,FFN_ROWS*FFN_COLS*2u,2)) return -4;
    uint32_t status=ffn_read(FFN_STATUS);
    if ((status & 1u) || !(status & 8u)) return -1;
    ffn_write(FFN_LAYER,layer); ffn_write(FFN_SHIFT,shift);
    ffn_write(FFN_X,x); ffn_write(FFN_W,w); ffn_write(FFN_B,b); ffn_write(FFN_Y,y);
    ffn_fence();
    ffn_write(FFN_CONTROL,1);
    do {
        status=ffn_read(FFN_STATUS);
        if (status & 4u) return -3;
        if (status & 2u) {
            ffn_fence();
            if (ffn_read(FFN_OUTPUTS)!=FFN_ROWS*FFN_COLS) return -3;
            if (cycles) *cycles=ffn_read(FFN_CYCLES);
            ffn_write(FFN_CONTROL,2);
            return 0;
        }
    } while (--max_polls);
    return -2;
}
