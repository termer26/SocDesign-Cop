#include "ffn_driver.h"
#define MAILBOX ((volatile uint32_t *)(uintptr_t)0xa0060000u)
/* Host mailbox: command, layer, shift, status, result, checksum, cycles, jobs.
 * The host supplies only encoded inputs/weights/bias. All dot products run in RTL.
 */
int main(void) {
    MAILBOX[0]=0; MAILBOX[3]=0xb007u; MAILBOX[7]=0;
    if (ffn_read(FFN_VERSION)!=0x00010000u) {
        MAILBOX[3]=0xbad1u;
        for (;;) __asm__ volatile ("wfi");
    }
    for (;;) {
        while (MAILBOX[0]==0) { __asm__ volatile ("nop"); }
        MAILBOX[3]=1;
        uint32_t cycles=0;
        int result=ffn_run(MAILBOX[1],MAILBOX[2],FFN_X_BASE,FFN_W_BASE,
                           FFN_B_BASE,FFN_Y_BASE,20000000u,&cycles);
        uint32_t sum=0;
        if (result==0) {
            volatile uint16_t *output=(volatile uint16_t *)(uintptr_t)FFN_Y_BASE;
            for (unsigned i=0;i<FFN_ROWS*FFN_COLS;++i) sum+=output[i];
        }
        MAILBOX[4]=(uint32_t)result; MAILBOX[5]=sum; MAILBOX[6]=cycles;
        MAILBOX[7]++; MAILBOX[0]=0;
        ffn_fence();
        MAILBOX[3]=result==0 ? 0x600du : 0xbad0u;
    }
}
