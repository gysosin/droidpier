//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <open_dex_texture/open_dex_texture_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) open_dex_texture_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "OpenDexTexturePlugin");
  open_dex_texture_plugin_register_with_registrar(open_dex_texture_registrar);
}
