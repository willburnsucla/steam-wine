/* d3d11test: minimal D3D11 end-to-end check, the way a game uses it.
 * Creates a window and a swapchain, clears the back buffer to a known color, presents a few
 * frames, then copies the back buffer to a staging texture and reads the center pixel back.
 * Prints the adapter name so we can tell DXMT (Apple GPU) from wined3d.
 * Build: x86_64-w64-mingw32-gcc -O2 -o d3d11test.exe d3d11test.c -ld3d11 -ldxgi -luuid -lgdi32
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    return DefWindowProcW(h, m, w, l);
}

int main(void)
{
    WNDCLASSW wc = {0};
    HWND hwnd;
    DXGI_SWAP_CHAIN_DESC sd = {0};
    ID3D11Device *dev = NULL;
    ID3D11DeviceContext *ctx = NULL;
    IDXGISwapChain *sc = NULL;
    ID3D11Texture2D *back = NULL, *staging = NULL;
    ID3D11RenderTargetView *rtv = NULL;
    D3D11_TEXTURE2D_DESC td;
    D3D11_MAPPED_SUBRESOURCE map;
    IDXGIDevice *dxgidev = NULL;
    IDXGIAdapter *adapter = NULL;
    DXGI_ADAPTER_DESC ad;
    D3D_FEATURE_LEVEL fl;
    const float color[4] = {0.2f, 0.6f, 1.0f, 1.0f}; /* expect ~ (51,153,255) */
    HRESULT hr;
    int i;

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"d3d11test";
    RegisterClassW(&wc);
    hwnd = CreateWindowW(L"d3d11test", L"d3d11test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                         100, 100, 320, 240, NULL, NULL, wc.hInstance, NULL);

    sd.BufferCount = 2;
    sd.BufferDesc.Width = 320;
    sd.BufferDesc.Height = 240;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;

    hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                       D3D11_SDK_VERSION, &sd, &sc, &dev, &fl, &ctx);
    printf("D3D11CreateDeviceAndSwapChain hr=0x%08lx feature_level=0x%x\n", hr, fl);
    if (FAILED(hr)) return 1;

    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgidev)) &&
        SUCCEEDED(IDXGIDevice_GetAdapter(dxgidev, &adapter)) &&
        SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &ad)))
        printf("adapter: %ls\n", ad.Description);

    hr = IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&back);
    if (FAILED(hr)) { printf("GetBuffer hr=0x%08lx\n", hr); return 1; }
    ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)back, NULL, &rtv);

    for (i = 0; i < 10; i++)
    {
        ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, color);
        hr = IDXGISwapChain_Present(sc, 1, 0);
        if (FAILED(hr)) { printf("Present hr=0x%08lx\n", hr); return 1; }
    }
    printf("presented 10 frames\n");

    /* Draw once more and read the back buffer back before presenting. */
    ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, color);
    ID3D11Texture2D_GetDesc(back, &td);
    td.Usage = D3D11_USAGE_STAGING;
    td.BindFlags = 0;
    td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    td.MiscFlags = 0;
    ID3D11Device_CreateTexture2D(dev, &td, NULL, &staging);
    ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)staging, (ID3D11Resource *)back);
    hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &map);
    if (FAILED(hr)) { printf("Map hr=0x%08lx\n", hr); return 1; }
    {
        const unsigned char *p = (const unsigned char *)map.pData + 120 * map.RowPitch + 160 * 4;
        printf("center pixel rgba=(%u,%u,%u,%u)\n", p[0], p[1], p[2], p[3]);
        printf("%s\n", (p[0] > 40 && p[0] < 60 && p[1] > 140 && p[1] < 165 && p[2] > 245)
                           ? "RESULT: PASS" : "RESULT: FAIL");
    }
    ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)staging, 0);
    DestroyWindow(hwnd);
    return 0;
}
