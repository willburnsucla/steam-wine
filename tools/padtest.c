/* padtest: which game controllers can Windows games see? Lists XInput slots 0-3 and DirectInput
 * game controllers (name, VID/PID), then prints XInput button/stick state for a few seconds so
 * button presses can be checked by eye. PASS iff at least one controller is listed.
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

static IDirectInput8W *di;
static int found;

static BOOL CALLBACK enum_cb(const DIDEVICEINSTANCEW *inst, void *ctx)
{
    IDirectInputDevice8W *dev;
    DIPROPDWORD vidpid = {{sizeof(vidpid), sizeof(DIPROPHEADER), 0, DIPH_DEVICE}};

    if (SUCCEEDED(IDirectInput8_CreateDevice(di, &inst->guidInstance, &dev, NULL)))
    {
        IDirectInputDevice8_GetProperty(dev, DIPROP_VIDPID, &vidpid.diph);
        IDirectInputDevice8_Release(dev);
    }
    printf("DirectInput: %ls (VID %04x PID %04x)\n", inst->tszProductName,
           (unsigned)LOWORD(vidpid.dwData), (unsigned)HIWORD(vidpid.dwData));
    found++;
    return DIENUM_CONTINUE;
}

int main(int argc, char **argv)
{
    int seconds = argc > 1 ? atoi(argv[1]) : 10, i, t;
    XINPUT_STATE state;
    BOOL xinput[4] = {0};

    for (i = 0; i < 4; i++)
        if (XInputGetState(i, &state) == ERROR_SUCCESS)
        {
            printf("XInput: controller in slot %d\n", i);
            xinput[i] = TRUE;
            found++;
        }

    if (SUCCEEDED(DirectInput8Create(GetModuleHandleW(NULL), DIRECTINPUT_VERSION, &IID_IDirectInput8W,
                                     (void **)&di, NULL)))
        IDirectInput8_EnumDevices(di, DI8DEVCLASS_GAMECTRL, enum_cb, NULL, DIEDFL_ATTACHEDONLY);

    printf("controllers: %d\n", found);
    for (t = 0; found && t < seconds * 4; t++)
    {
        for (i = 0; i < 4; i++)
            if (xinput[i] && XInputGetState(i, &state) == ERROR_SUCCESS)
                printf("slot %d buttons %04x left stick %6d,%6d\n", i, state.Gamepad.wButtons,
                       state.Gamepad.sThumbLX, state.Gamepad.sThumbLY);
        Sleep(250);
    }
    printf("RESULT: %s\n", found ? "PASS" : "FAIL");
    return 0;
}
