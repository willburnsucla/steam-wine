/* memtest: how much address space does a 32-bit game get? Reserves 64 MB blocks until
 * VirtualAlloc fails and prints the total. Built without the large-address-aware flag, like
 * Fallout 3 / New Vegas, so it only passes when Wine grants 4 GB (WINE_LARGE_ADDRESS_AWARE=1).
 * PASS iff more than 3000 MB could be reserved and a page above 2 GB can be committed and written.
 * Fails as "test invalid" if the exe itself is marked large-address-aware.
 * Build: i686-w64-mingw32-gcc -O2 -o memtest32.exe memtest.c -Wl,--disable-large-address-aware
 */
#include <windows.h>
#include <stdio.h>

int main(void)
{
    const SIZE_T chunk = 64 << 20;
    const IMAGE_NT_HEADERS *nt;
    BYTE *base = (BYTE *)GetModuleHandleW(NULL), *p, *highest = NULL;
    unsigned int mb = 0;
    int wrote = 0;

    nt = (const IMAGE_NT_HEADERS *)(base + ((const IMAGE_DOS_HEADER *)base)->e_lfanew);
    if (nt->FileHeader.Characteristics & IMAGE_FILE_LARGE_ADDRESS_AWARE)
    {
        printf("RESULT: FAIL (exe is marked large-address-aware, test invalid)\n");
        return 1;
    }
    while ((p = VirtualAlloc(NULL, chunk, MEM_RESERVE, PAGE_NOACCESS)))
    {
        mb += 64;
        if (p > highest) highest = p;
    }
    /* Use memory above 2 GB, not just reserve it. */
    if (highest >= (BYTE *)0x80000000 && VirtualAlloc(highest, 4096, MEM_COMMIT, PAGE_READWRITE))
    {
        *(volatile int *)highest = 1;
        wrote = *(volatile int *)highest == 1;
    }
    printf("reserved %u MB in a %d-bit process, highest block %p, wrote above 2 GB: %s\n",
           mb, (int)sizeof(void *) * 8, (void *)highest, wrote ? "yes" : "no");
    if (mb > 3000 && wrote)
    {
        printf("RESULT: PASS\n");
        return 0;
    }
    printf("RESULT: FAIL\n");
    return 1;
}
