/* memtest: how much address space does a 32-bit game get? Reserves 64 MB blocks until
 * VirtualAlloc fails and prints the total. Built without the large-address-aware flag, like
 * Fallout 3 / New Vegas, so it only passes when Wine grants 4 GB (WINE_LARGE_ADDRESS_AWARE=1).
 * PASS iff more than 3000 MB could be reserved.
 * Build: i686-w64-mingw32-gcc -O2 -o memtest32.exe memtest.c
 */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    const SIZE_T chunk = 64 << 20;
    unsigned int mb = 0;

    while (VirtualAlloc(NULL, chunk, MEM_RESERVE, PAGE_NOACCESS))
        mb += 64;
    printf("reserved %u MB in a %d-bit process\n", mb, (int)sizeof(void *) * 8);
    printf("RESULT: %s\n", mb > 3000 ? "PASS" : "FAIL");
    return 0;
}
