/* steamwebhelper wrapper: start the real helper (steamwebhelper_real.exe, same folder) with
 * extra Chromium flags in front of Steam's own arguments.
 *
 * Why: on Wine's macOS driver a process can't draw into a window owned by another process.
 * Steam's helper puts its compositor in a separate GPU process that draws into the browser
 * process's window, so the window stays black. --in-process-gpu keeps the compositor in the
 * process that owns the window.
 *
 * Flags: STEAMWEBHELPER_EXTRA_FLAGS from the environment, default "--in-process-gpu".
 * The real helper is put in a job object that is killed when the wrapper exits, so Steam
 * terminating the wrapper also ends the helper.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -municode -mwindows -o steamwebhelper.exe webhelper-wrapper.c
 */
#include <windows.h>
#include <wchar.h>
#include <stdlib.h>

static const WCHAR *skip_argv0(const WCHAR *cmd)
{
    if (*cmd == L'"')
    {
        cmd++;
        while (*cmd && *cmd != L'"') cmd++;
        if (*cmd) cmd++;
    }
    else
        while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
    while (*cmd == L' ' || *cmd == L'\t') cmd++;
    return cmd;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, LPWSTR unused, int show)
{
    WCHAR real[MAX_PATH], flags[1024], *slash, *cmd;
    const WCHAR *args = skip_argv0(GetCommandLineW());
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
    STARTUPINFOW si = {sizeof(si)};
    PROCESS_INFORMATION pi;
    HANDLE job;
    DWORD code = 1;
    size_t len;

    GetModuleFileNameW(NULL, real, MAX_PATH);
    if ((slash = wcsrchr(real, L'\\'))) slash[1] = 0;
    wcscat(real, L"steamwebhelper_real.exe");

    if (!GetEnvironmentVariableW(L"STEAMWEBHELPER_EXTRA_FLAGS", flags, ARRAYSIZE(flags)))
        wcscpy(flags, L"--in-process-gpu");

    len = wcslen(real) + wcslen(flags) + wcslen(args) + 8;
    cmd = malloc(len * sizeof(WCHAR));
    swprintf(cmd, len, L"\"%ls\" %ls %ls", real, flags, args);

    job = CreateJobObjectW(NULL, NULL);
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits));

    GetStartupInfoW(&si);
    if (!CreateProcessW(real, cmd, NULL, NULL, TRUE, CREATE_SUSPENDED, NULL, NULL, &si, &pi))
        return GetLastError();
    AssignProcessToJobObject(job, pi.hProcess);
    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);

    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &code);
    return (int)code;
}
