/* winlist: list visible top-level windows, optionally capture one to a BMP.
 * Usage: winlist.exe                 list visible windows
 *        winlist.exe all             list all top-level windows
 *        winlist.exe <hwnd> <out.bmp> capture window via PrintWindow
 *        winlist.exe <hwnd> <out.bmp> dc   capture by BitBlt from the window DC
 * Build: x86_64-w64-mingw32-gcc -O2 -o winlist.exe winlist.c -lgdi32 -luser32
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static BOOL CALLBACK list_cb(HWND hwnd, LPARAM lp)
{
    char title[256], cls[256];
    RECT r;
    DWORD pid;
    if (!lp && !IsWindowVisible(hwnd)) return TRUE;
    GetWindowTextA(hwnd, title, sizeof(title));
    GetClassNameA(hwnd, cls, sizeof(cls));
    GetWindowRect(hwnd, &r);
    GetWindowThreadProcessId(hwnd, &pid);
    printf("%s %p pid=%lu %ldx%ld+%ld+%ld class=\"%s\" title=\"%s\"\n", IsWindowVisible(hwnd) ? "V" : "-", (void *)hwnd, pid,
           r.right - r.left, r.bottom - r.top, r.left, r.top, cls, title);
    return TRUE;
}

static int capture(HWND hwnd, const char *path, int use_dc)
{
    RECT r;
    int w, h;
    HDC wdc, mdc;
    HBITMAP bmp;
    BITMAPINFOHEADER bi = {0};
    BITMAPFILEHEADER bf = {0};
    void *bits;
    FILE *f;
    BOOL ok;

    GetWindowRect(hwnd, &r);
    w = r.right - r.left; h = r.bottom - r.top;
    if (w <= 0 || h <= 0) return 1;
    wdc = GetDC(NULL);
    mdc = CreateCompatibleDC(wdc);
    bi.biSize = sizeof(bi); bi.biWidth = w; bi.biHeight = -h; bi.biPlanes = 1; bi.biBitCount = 32;
    bmp = CreateDIBSection(wdc, (BITMAPINFO *)&bi, DIB_RGB_COLORS, &bits, NULL, 0);
    SelectObject(mdc, bmp);
    if (use_dc)
    {
        /* Copy straight from the window's surface instead of asking it to repaint. */
        HDC hdc = GetWindowDC(hwnd);
        ok = BitBlt(mdc, 0, 0, w, h, hdc, 0, 0, SRCCOPY);
        ReleaseDC(hwnd, hdc);
    }
    else
    {
        ok = PrintWindow(hwnd, mdc, 2 /* PW_RENDERFULLCONTENT */);
        if (!ok) ok = BitBlt(mdc, 0, 0, w, h, wdc, r.left, r.top, SRCCOPY);
    }
    GdiFlush();
    bf.bfType = 0x4d42;
    bf.bfOffBits = sizeof(bf) + sizeof(bi);
    bf.bfSize = bf.bfOffBits + w * h * 4;
    bi.biHeight = -h;
    if (!(f = fopen(path, "wb"))) return 2;
    fwrite(&bf, sizeof(bf), 1, f);
    fwrite(&bi, sizeof(bi), 1, f);
    fwrite(bits, 4, (size_t)w * h, f);
    fclose(f);
    printf("captured %dx%d ok=%d\n", w, h, ok);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 3) return capture((HWND)(ULONG_PTR)strtoull(argv[1], NULL, 16), argv[2],
                                  argc == 4 && !strcmp(argv[3], "dc"));
    EnumWindows(list_cb, argc == 2); /* any arg: include hidden windows */
    printf("done\n");
    fflush(stdout);
    return 0;
}
