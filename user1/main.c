#include "lib.h"

int main(void)
{
    while (1) {
        printf("process1\n");
        sleepu(10000);
    }
    return 0;
}