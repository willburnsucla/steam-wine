/* d3d9test: minimal D3D9 end-to-end check (the API of Oblivion, Fallout 3, New Vegas).
 * Creates a windowed device, clears to a known color, presents 10 frames, then reads the back
 * buffer back through GetRenderTargetData and checks the center pixel.
 * Build: i686-w64-mingw32-gcc -O2 -o d3d9test32.exe d3d9test.c -ld3d9   (32-bit, like those games)
 *        x86_64-w64-mingw32-gcc -O2 -o d3d9test.exe d3d9test.c -ld3d9
 */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>

#define W 320
#define H 240

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    return DefWindowProcW(h, m, w, l);
}

int main(void)
{
    WNDCLASSW wc = {0};
    HWND hwnd;
    IDirect3D9 *d3d;
    IDirect3DDevice9 *dev;
    IDirect3DSurface9 *back, *sys;
    D3DPRESENT_PARAMETERS pp = {0};
    D3DADAPTER_IDENTIFIER9 id;
    D3DLOCKED_RECT lr;
    HRESULT hr;
    BYTE *p;
    int i;

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"d3d9test";
    RegisterClassW(&wc);
    hwnd = CreateWindowW(L"d3d9test", L"d3d9test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                         100, 100, W, H, NULL, NULL, wc.hInstance, NULL);

    if (!(d3d = Direct3DCreate9(D3D_SDK_VERSION))) { printf("Direct3DCreate9 failed\nRESULT: FAIL\n"); return 1; }
    if (SUCCEEDED(IDirect3D9_GetAdapterIdentifier(d3d, D3DADAPTER_DEFAULT, 0, &id)))
        printf("adapter: %s (%d-bit process)\n", id.Description, (int)sizeof(void *) * 8);

    pp.Windowed = TRUE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_X8R8G8B8;
    pp.BackBufferWidth = W;
    pp.BackBufferHeight = H;
    pp.hDeviceWindow = hwnd;
    hr = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hwnd,
                                 D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
    printf("CreateDevice hr=0x%08lx\n", hr);
    if (FAILED(hr)) { printf("RESULT: FAIL\n"); return 1; }

    for (i = 0; i < 10; i++)
    {
        IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(51, 153, 255), 1.0f, 0);
        hr = IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
        if (FAILED(hr)) { printf("Present hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }
    }
    printf("presented 10 frames\n");

    IDirect3DDevice9_Clear(dev, 0, NULL, D3DCLEAR_TARGET, D3DCOLOR_XRGB(51, 153, 255), 1.0f, 0);
    IDirect3DDevice9_GetRenderTarget(dev, 0, &back);
    IDirect3DDevice9_CreateOffscreenPlainSurface(dev, W, H, D3DFMT_X8R8G8B8, D3DPOOL_SYSTEMMEM, &sys, NULL);
    hr = IDirect3DDevice9_GetRenderTargetData(dev, back, sys);
    if (FAILED(hr)) { printf("GetRenderTargetData hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }
    IDirect3DSurface9_LockRect(sys, &lr, NULL, D3DLOCK_READONLY);
    p = (BYTE *)lr.pBits + (H / 2) * lr.Pitch + (W / 2) * 4; /* BGRX */
    printf("center pixel rgb=(%u,%u,%u)\n", p[2], p[1], p[0]);
    printf("%s\n", (p[2] == 51 && p[1] == 153 && p[0] == 255) ? "RESULT: PASS" : "RESULT: FAIL");
    IDirect3DSurface9_UnlockRect(sys);
    DestroyWindow(hwnd);
    return 0;
}
