/* d3d12test: minimal D3D12 end-to-end check, the way a game uses it.
 * Device, direct queue, flip-model swapchain on a window, clear the back buffer to a known
 * color, present 10 frames, then copy the back buffer to a readback buffer and check the
 * center pixel. Prints the adapter name.
 * Build: x86_64-w64-mingw32-gcc -O2 -o d3d12test.exe d3d12test.c -ld3d12 -ldxgi -luuid
 */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#include <windows.h>
#include <initguid.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>

#define W 320
#define H 240
#define CHECK(x) do { HRESULT hr_ = (x); if (FAILED(hr_)) { printf("%s failed hr=0x%08lx\nRESULT: FAIL\n", #x, hr_); return 1; } } while (0)

static ID3D12Device *dev;
static ID3D12CommandQueue *queue;
static ID3D12Fence *fence;
static UINT64 fence_value;
static HANDLE fence_event;

static void wait_gpu(void)
{
    ID3D12CommandQueue_Signal(queue, fence, ++fence_value);
    if (ID3D12Fence_GetCompletedValue(fence) < fence_value)
    {
        ID3D12Fence_SetEventOnCompletion(fence, fence_value, fence_event);
        WaitForSingleObject(fence_event, 5000);
    }
}

static void barrier(ID3D12GraphicsCommandList *list, ID3D12Resource *res,
                    D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after)
{
    D3D12_RESOURCE_BARRIER b = {0};
    b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    b.Transition.pResource = res;
    b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    b.Transition.StateBefore = before;
    b.Transition.StateAfter = after;
    ID3D12GraphicsCommandList_ResourceBarrier(list, 1, &b);
}

static LRESULT CALLBACK wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    return DefWindowProcW(h, m, w, l);
}

int main(void)
{
    WNDCLASSW wc = {0};
    HWND hwnd;
    IDXGIFactory4 *factory;
    IDXGISwapChain1 *sc1;
    IDXGISwapChain3 *sc;
    IDXGIAdapter1 *adapter;
    DXGI_ADAPTER_DESC1 ad;
    DXGI_SWAP_CHAIN_DESC1 sd = {0};
    D3D12_COMMAND_QUEUE_DESC qd = {0};
    D3D12_DESCRIPTOR_HEAP_DESC hd = {0};
    ID3D12DescriptorHeap *rtv_heap;
    D3D12_CPU_DESCRIPTOR_HANDLE rtv[2];
    UINT rtv_size, i, idx;
    ID3D12Resource *back[2], *readback;
    ID3D12CommandAllocator *alloc;
    ID3D12GraphicsCommandList *list;
    D3D12_HEAP_PROPERTIES hp = {0};
    D3D12_RESOURCE_DESC rd = {0}, bd;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp;
    UINT64 total;
    D3D12_TEXTURE_COPY_LOCATION dst = {0}, src = {0};
    D3D12_RANGE range = {0, 0};
    const float color[4] = {0.2f, 0.6f, 1.0f, 1.0f}; /* expect ~ (51,153,255) */
    LUID luid;
    BYTE *p;

    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"d3d12test";
    RegisterClassW(&wc);
    hwnd = CreateWindowW(L"d3d12test", L"d3d12test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                         100, 100, W, H, NULL, NULL, wc.hInstance, NULL);

    CHECK(D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&dev));
    CHECK(CreateDXGIFactory2(0, &IID_IDXGIFactory4, (void **)&factory));
    luid = ID3D12Device_GetAdapterLuid(dev);
    if (SUCCEEDED(IDXGIFactory4_EnumAdapterByLuid(factory, luid, &IID_IDXGIAdapter1, (void **)&adapter)) &&
        SUCCEEDED(IDXGIAdapter1_GetDesc1(adapter, &ad)))
        printf("adapter: %ls\n", ad.Description);

    qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    CHECK(ID3D12Device_CreateCommandQueue(dev, &qd, &IID_ID3D12CommandQueue, (void **)&queue));
    CHECK(ID3D12Device_CreateFence(dev, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence));
    fence_event = CreateEventW(NULL, FALSE, FALSE, NULL);

    sd.Width = W; sd.Height = H;
    sd.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = 2;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    CHECK(IDXGIFactory4_CreateSwapChainForHwnd(factory, (IUnknown *)queue, hwnd, &sd, NULL, NULL, &sc1));
    CHECK(IDXGISwapChain1_QueryInterface(sc1, &IID_IDXGISwapChain3, (void **)&sc));

    hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    hd.NumDescriptors = 2;
    CHECK(ID3D12Device_CreateDescriptorHeap(dev, &hd, &IID_ID3D12DescriptorHeap, (void **)&rtv_heap));
    rtv_size = ID3D12Device_GetDescriptorHandleIncrementSize(dev, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    rtv[0] = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(rtv_heap);
    rtv[1].ptr = rtv[0].ptr + rtv_size;
    for (i = 0; i < 2; i++)
    {
        CHECK(IDXGISwapChain3_GetBuffer(sc, i, &IID_ID3D12Resource, (void **)&back[i]));
        ID3D12Device_CreateRenderTargetView(dev, back[i], NULL, rtv[i]);
    }

    CHECK(ID3D12Device_CreateCommandAllocator(dev, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                              &IID_ID3D12CommandAllocator, (void **)&alloc));
    CHECK(ID3D12Device_CreateCommandList(dev, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, NULL,
                                         &IID_ID3D12GraphicsCommandList, (void **)&list));
    ID3D12GraphicsCommandList_Close(list);

    for (i = 0; i < 10; i++)
    {
        idx = IDXGISwapChain3_GetCurrentBackBufferIndex(sc);
        ID3D12CommandAllocator_Reset(alloc);
        ID3D12GraphicsCommandList_Reset(list, alloc, NULL);
        barrier(list, back[idx], D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_RENDER_TARGET);
        ID3D12GraphicsCommandList_ClearRenderTargetView(list, rtv[idx], color, 0, NULL);
        barrier(list, back[idx], D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_PRESENT);
        ID3D12GraphicsCommandList_Close(list);
        ID3D12CommandQueue_ExecuteCommandLists(queue, 1, (ID3D12CommandList **)&list);
        CHECK(IDXGISwapChain3_Present(sc, 1, 0));
        wait_gpu();
    }
    printf("presented 10 frames\n");

    /* Clear once more and copy the back buffer to a readback buffer. */
    idx = IDXGISwapChain3_GetCurrentBackBufferIndex(sc);
    bd = ID3D12Resource_GetDesc(back[idx]);
    ID3D12Device_GetCopyableFootprints(dev, &bd, 0, 1, 0, &fp, NULL, NULL, &total);
    hp.Type = D3D12_HEAP_TYPE_READBACK;
    rd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    rd.Width = total;
    rd.Height = 1; rd.DepthOrArraySize = 1; rd.MipLevels = 1;
    rd.SampleDesc.Count = 1;
    rd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    CHECK(ID3D12Device_CreateCommittedResource(dev, &hp, D3D12_HEAP_FLAG_NONE, &rd, D3D12_RESOURCE_STATE_COPY_DEST,
                                               NULL, &IID_ID3D12Resource, (void **)&readback));
    ID3D12CommandAllocator_Reset(alloc);
    ID3D12GraphicsCommandList_Reset(list, alloc, NULL);
    barrier(list, back[idx], D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_RENDER_TARGET);
    ID3D12GraphicsCommandList_ClearRenderTargetView(list, rtv[idx], color, 0, NULL);
    barrier(list, back[idx], D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_COPY_SOURCE);
    src.pResource = back[idx];
    src.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    src.SubresourceIndex = 0;
    dst.pResource = readback;
    dst.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    dst.PlacedFootprint = fp;
    ID3D12GraphicsCommandList_CopyTextureRegion(list, &dst, 0, 0, 0, &src, NULL);
    barrier(list, back[idx], D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_PRESENT);
    ID3D12GraphicsCommandList_Close(list);
    ID3D12CommandQueue_ExecuteCommandLists(queue, 1, (ID3D12CommandList **)&list);
    wait_gpu();

    CHECK(ID3D12Resource_Map(readback, 0, NULL, (void **)&p));
    p += fp.Offset + (H / 2) * fp.Footprint.RowPitch + (W / 2) * 4;
    printf("center pixel rgba=(%u,%u,%u,%u)\n", p[0], p[1], p[2], p[3]);
    printf("%s\n", (p[0] > 40 && p[0] < 60 && p[1] > 140 && p[1] < 165 && p[2] > 245)
                       ? "RESULT: PASS" : "RESULT: FAIL");
    ID3D12Resource_Unmap(readback, 0, &range);
    DestroyWindow(hwnd);
    return 0;
}
