#ifndef FLUTTER_PLUGIN_OPEN_DEX_TEXTURE_PLUGIN_H_
#define FLUTTER_PLUGIN_OPEN_DEX_TEXTURE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _OpenDexTexturePlugin OpenDexTexturePlugin;
typedef struct {
  GObjectClass parent_class;
} OpenDexTexturePluginClass;

FLUTTER_PLUGIN_EXPORT GType open_dex_texture_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void open_dex_texture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif
