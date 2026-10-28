/* padtest: which game controllers can Windows games see, and do their buttons work?
 * For the whole run it polls XInput slots 0-3 and re-enumerates DirectInput game controllers
 * once a second (Wine adds a controller a moment after its bus starts, so a single look at
 * startup can miss it). It prints each controller once when it appears, then button/stick state
 * a few times a second: XInput pads through XInput, DirectInput-only pads (PS4/PS5, flight
 * sticks) through DirectInput.
 * PASS iff at least one controller was seen.
 * Usage: padtest.exe [seconds]   (default 10)
 * Build: x86_64-w64-mingw32-gcc -O2 -o padtest.exe padtest.c -ldinput8 -ldxguid -lxinput -lole32
 */
#define COBJMACROS
#define DIRECTINPUT_VERSION 0x0800
#include <windows.h>
#include <dinput.h>
#include <xinput.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_DI 8

static IDirectInput8W *di;
static struct { GUID guid; IDirectInputDevice8W *dev; WCHAR name[MAX_PATH]; BOOL xinput; } pads[MAX_DI];
static int npads;

/* Wine's XInput devices also appear in DirectInput with "IG_" in their device path. */
static BOOL is_xinput_device(IDirectInputDevice8W *dev)
{
    DIPROPGUIDANDPATH prop = {{sizeof(prop), sizeof(DIPROPHEADER), 0, DIPH_DEVICE}};
    if (FAILED(IDirectInputDevice8_GetProperty(dev, DIPROP_GUIDANDPATH, &prop.diph))) return FALSE;
    return wcsstr(prop.wszPath, L"IG_") || wcsstr(prop.wszPath, L"ig_");
}

static BOOL CALLBACK enum_cb(const DIDEVICEINSTANCEW *inst, void *ctx)
{
    DIPROPDWORD vidpid = {{sizeof(vidpid), sizeof(DIPROPHEADER), 0, DIPH_DEVICE}};
    IDirectInputDevice8W *dev;
    int i;

    for (i = 0; i < npads; i++)
        if (IsEqualGUID(&pads[i].guid, &inst->guidInstance)) return DIENUM_CONTINUE;
    if (npads == MAX_DI || FAILED(IDirectInput8_CreateDevice(di, &inst->guidInstance, &dev, NULL)))
        return DIENUM_CONTINUE;
    IDirectInputDevice8_GetProperty(dev, DIPROP_VIDPID, &vidpid.diph);
    pads[npads].guid = inst->guidInstance;
    pads[npads].dev = dev;
    pads[npads].xinput = is_xinput_device(dev);
    lstrcpynW(pads[npads].name, inst->tszProductName, MAX_PATH);
    IDirectInputDevice8_SetDataFormat(dev, &c_dfDIJoystick2);
    IDirectInputDevice8_Acquire(dev);
    printf("new DirectInput controller: %ls (VID %04x PID %04x)%s\n", inst->tszProductName,
           (unsigned)LOWORD(vidpid.dwData), (unsigned)HIWORD(vidpid.dwData),
           pads[npads].xinput ? " [also XInput]" : "");
    npads++;
    return DIENUM_CONTINUE;
}

int main(int argc, char **argv)
{
    int seconds = argc > 1 ? atoi(argv[1]) : 10, tick, i, j, xinput_count = 0, di_only;
    BOOL xinput_seen[4] = {0};
    XINPUT_STATE state;
    DIJOYSTATE2 js;

    if (FAILED(DirectInput8Create(GetModuleHandleW(NULL), DIRECTINPUT_VERSION, &IID_IDirectInput8W,
                                  (void **)&di, NULL)))
    {
        printf("DirectInput8Create failed; only XInput is checked\n");
        di = NULL;
    }

    for (tick = 0; tick < seconds * 4; tick++)
    {
        if (di && tick % 4 == 0)
            IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, enum_cb, NULL, DIEDFL_ATTACHEDONLY);

        for (i = 0; i < 4; i++)
        {
            if (XInputGetState(i, &state) != ERROR_SUCCESS) continue;
            if (!xinput_seen[i])
            {
                printf("new XInput controller in slot %d\n", i);
                xinput_seen[i] = TRUE;
                xinput_count++;
            }
            printf("XInput %d: buttons %04x left stick %6d,%6d\n", i, state.Gamepad.wButtons,
                   state.Gamepad.sThumbLX, state.Gamepad.sThumbLY);
        }
        for (i = 0; i < npads; i++)
        {
            unsigned int buttons = 0;
            if (pads[i].xinput) continue; /* already shown through XInput */
            IDirectInputDevice8_Poll(pads[i].dev);
            if (FAILED(IDirectInputDevice8_GetDeviceState(pads[i].dev, sizeof(js), &js))) continue;
            for (j = 0; j < 32; j++) if (js.rgbButtons[j] & 0x80) buttons |= 1u << j;
            printf("DirectInput %ls: buttons %08x x/y %ld,%ld\n", pads[i].name, buttons, js.lX, js.lY);
        }
        Sleep(250);
    }

    /* One physical XInput pad shows up in both APIs; count it once. */
    di_only = 0;
    for (i = 0; i < npads; i++) if (!pads[i].xinput) di_only++;
    printf("controllers: %d (XInput %d, DirectInput-only %d)\n", xinput_count + di_only, xinput_count, di_only);
    printf("RESULT: %s\n", xinput_count + di_only ? "PASS" : "FAIL");
    return xinput_count + di_only ? 0 : 1;
}
