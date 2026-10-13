/* vktest: does Vulkan work in this Wine? Loads vulkan-1.dll, creates an instance and lists
 * physical devices. Minimal hand-written declarations so it builds without Vulkan headers.
 * Build: x86_64-w64-mingw32-gcc -O2 -o vktest.exe vktest.c
 */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

typedef int32_t VkResult;
typedef void *VkInstance;
typedef void *VkPhysicalDevice;
typedef struct { int sType; const void *pNext; const char *pApplicationName; uint32_t appVer;
                 const char *pEngineName; uint32_t engVer; uint32_t apiVersion; } VkApplicationInfo;
typedef struct { int sType; const void *pNext; uint32_t flags; const VkApplicationInfo *pApplicationInfo;
                 uint32_t layerCount; const char *const *layers; uint32_t extCount;
                 const char *const *exts; } VkInstanceCreateInfo;
typedef struct { uint32_t apiVersion, driverVersion, vendorID, deviceID; int deviceType;
                 char deviceName[256]; uint8_t uuid[16]; char rest[4096]; } VkPhysicalDeviceProperties;

typedef VkResult (__stdcall *PFN_create)(const VkInstanceCreateInfo *, const void *, VkInstance *);
typedef VkResult (__stdcall *PFN_enum)(VkInstance, uint32_t *, VkPhysicalDevice *);
typedef void (__stdcall *PFN_props)(VkPhysicalDevice, VkPhysicalDeviceProperties *);
typedef void (__stdcall *PFN_destroy)(VkInstance, const void *);

int main(void)
{
    HMODULE vk = LoadLibraryA("vulkan-1.dll");
    PFN_create create; PFN_enum enumdev; PFN_props props; PFN_destroy destroy;
    VkApplicationInfo app = {0}; VkInstanceCreateInfo ci = {0};
    VkInstance inst = NULL; VkPhysicalDevice devs[8]; uint32_t n = 8, i; VkResult r;

    if (!vk) { printf("vulkan-1.dll not loadable (%lu)\nRESULT: FAIL\n", GetLastError()); return 1; }
    create = (PFN_create)GetProcAddress(vk, "vkCreateInstance");
    enumdev = (PFN_enum)GetProcAddress(vk, "vkEnumeratePhysicalDevices");
    props = (PFN_props)GetProcAddress(vk, "vkGetPhysicalDeviceProperties");
    destroy = (PFN_destroy)GetProcAddress(vk, "vkDestroyInstance");
    app.sType = 0; /* VK_STRUCTURE_TYPE_APPLICATION_INFO */
    app.apiVersion = (1u << 22) | (1u << 12); /* 1.1 */
    ci.sType = 1; /* VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO */
    ci.pApplicationInfo = &app;
    r = create(&ci, NULL, &inst);
    printf("vkCreateInstance = %d\n", r);
    if (r) { printf("RESULT: FAIL\n"); return 1; }
    r = enumdev(inst, &n, devs);
    printf("vkEnumeratePhysicalDevices = %d, count %u\n", r, n);
    for (i = 0; i < n; i++)
    {
        VkPhysicalDeviceProperties p;
        memset(&p, 0, sizeof(p));
        props(devs[i], &p);
        printf("  device %u: %s (Vulkan %u.%u)\n", i, p.deviceName, p.apiVersion >> 22, (p.apiVersion >> 12) & 0x3ff);
    }
    printf("RESULT: %s\n", (r == 0 && n > 0) ? "PASS" : "FAIL");
    destroy(inst, NULL);
    return 0;
}
