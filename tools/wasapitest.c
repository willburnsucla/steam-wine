/* wasapitest: print the default render device's mix format, then open a shared-mode stream with
 * it and play 0.2 s of silence (no audible output). Checks that a 5.1 mix format on a stereo
 * device is accepted end to end.
 * Build: x86_64-w64-mingw32-gcc -O2 -o wasapitest.exe wasapitest.c -lole32 -luuid
 */
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <stdio.h>

DEFINE_GUID(CLSID_MMDeviceEnumerator_, 0xbcde0395, 0xe52f, 0x467c, 0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e);
DEFINE_GUID(IID_IMMDeviceEnumerator_, 0xa95664d2, 0x9614, 0x4f35, 0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6);
DEFINE_GUID(IID_IAudioClient_, 0x1cb9ad4c, 0xdbfa, 0x4c32, 0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2);
DEFINE_GUID(IID_IAudioRenderClient_, 0xf294acfc, 0x3146, 0x4483, 0xa7, 0xbf, 0xad, 0xdc, 0xa7, 0xc2, 0x60, 0xe2);

int main(void)
{
    IMMDeviceEnumerator *en; IMMDevice *dev; IAudioClient *ac; IAudioRenderClient *rc;
    WAVEFORMATEX *wf; WAVEFORMATEXTENSIBLE *wfx; UINT32 frames; BYTE *buf; HRESULT hr;

    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    hr = CoCreateInstance(&CLSID_MMDeviceEnumerator_, NULL, CLSCTX_ALL, &IID_IMMDeviceEnumerator_, (void **)&en);
    if (FAILED(hr)) { printf("enumerator hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }
    hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(en, eRender, eConsole, &dev);
    if (FAILED(hr)) { printf("no default render device hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }
    hr = IMMDevice_Activate(dev, &IID_IAudioClient_, CLSCTX_ALL, NULL, (void **)&ac);
    if (FAILED(hr) || !ac) { printf("Activate hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }
    hr = IAudioClient_GetMixFormat(ac, &wf);
    if (FAILED(hr) || !wf) { printf("GetMixFormat hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }
    wfx = (WAVEFORMATEXTENSIBLE *)wf;
    printf("mix format: %u ch, %lu Hz, %u bits, mask 0x%lx\n", wf->nChannels, wf->nSamplesPerSec,
           wf->wBitsPerSample, wf->wFormatTag == WAVE_FORMAT_EXTENSIBLE ? wfx->dwChannelMask : 0);
    hr = IAudioClient_Initialize(ac, AUDCLNT_SHAREMODE_SHARED, 0, 2000000, 0, wf, NULL);
    printf("Initialize hr=0x%08lx\n", hr);
    if (FAILED(hr)) { printf("RESULT: FAIL\n"); return 1; }
    IAudioClient_GetBufferSize(ac, &frames);
    hr = IAudioClient_GetService(ac, &IID_IAudioRenderClient_, (void **)&rc);
    if (FAILED(hr) || !rc) { printf("GetService hr=0x%08lx\nRESULT: FAIL\n", hr); return 1; }
    hr = IAudioRenderClient_GetBuffer(rc, frames, &buf);
    if (SUCCEEDED(hr)) hr = IAudioRenderClient_ReleaseBuffer(rc, frames, AUDCLNT_BUFFERFLAGS_SILENT);
    printf("silent buffer of %u frames hr=0x%08lx\n", frames, hr);
    IAudioClient_Start(ac);
    Sleep(200);
    IAudioClient_Stop(ac);
    printf("RESULT: %s\n", SUCCEEDED(hr) ? "PASS" : "FAIL");
    return 0;
}
