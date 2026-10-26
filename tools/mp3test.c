/* mp3test: play an MP3 through DirectShow, the way Fallout 3/New Vegas and Oblivion play music.
 * Builds a filter graph for C:\silence.mp3 (made by make-silent-mp3.py), prints the filters
 * DirectShow chose, runs it and waits for the end of the stream.
 * PASS iff RenderFile succeeds and EC_COMPLETE arrives within the duration + 5 s.
 * Build: i686-w64-mingw32-gcc -O2 -o mp3test32.exe mp3test.c -lole32 -lstrmiids -luuid
 *        x86_64-w64-mingw32-gcc -O2 -o mp3test.exe mp3test.c -lole32 -lstrmiids -luuid
 */
#define COBJMACROS
#include <windows.h>
#include <dshow.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    IGraphBuilder *graph;
    IMediaControl *control;
    IMediaEvent *event;
    IEnumFilters *filters;
    IBaseFilter *filter;
    FILTER_INFO info;
    long code = 0;
    LONG timeout_ms = (argc > 1 ? atoi(argv[1]) : 3) * 1000 + 5000;
    HRESULT hr;

    CoInitialize(NULL);
    hr = CoCreateInstance(&CLSID_FilterGraph, NULL, CLSCTX_INPROC_SERVER, &IID_IGraphBuilder, (void **)&graph);
    if (FAILED(hr)) { printf("FilterGraph hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }

    hr = IGraphBuilder_RenderFile(graph, L"C:\\silence.mp3", NULL);
    printf("RenderFile hr=0x%08lx\n", hr);
    if (hr != S_OK) { printf("RESULT: FAIL\n"); return 1; }

    if (SUCCEEDED(IGraphBuilder_EnumFilters(graph, &filters)))
    {
        while (IEnumFilters_Next(filters, 1, &filter, NULL) == S_OK)
        {
            if (SUCCEEDED(IBaseFilter_QueryFilterInfo(filter, &info)))
            {
                printf("filter: %ls\n", info.achName);
                if (info.pGraph) IFilterGraph_Release(info.pGraph);
            }
            IBaseFilter_Release(filter);
        }
        IEnumFilters_Release(filters);
    }

    IGraphBuilder_QueryInterface(graph, &IID_IMediaControl, (void **)&control);
    IGraphBuilder_QueryInterface(graph, &IID_IMediaEvent, (void **)&event);
    hr = IMediaControl_Run(control);
    printf("Run hr=0x%08lx\n", hr);
    hr = IMediaEvent_WaitForCompletion(event, timeout_ms, &code);
    printf("WaitForCompletion hr=0x%08lx event=%ld\n", hr, code);
    printf("RESULT: %s\n", (hr == S_OK && code == EC_COMPLETE) ? "PASS" : "FAIL");
    return 0;
}
