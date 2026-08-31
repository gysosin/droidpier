#ifndef OPEN_DEX_TEXTURE_PLUGIN_C_API_H_
#define OPEN_DEX_TEXTURE_PLUGIN_C_API_H_
#include <flutter_plugin_registrar.h>
#ifdef FLUTTER_PLUGIN_IMPL
#define DROIDPIER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define DROIDPIER_PLUGIN_EXPORT __declspec(dllimport)
#endif
#ifdef __cplusplus
extern "C" {
#endif
DROIDPIER_PLUGIN_EXPORT void OpenDexTexturePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
#ifdef __cplusplus
}
#endif
#endif
