#include "include/open_dex_texture/open_dex_texture_plugin.h"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>

#define OPEN_DEX_TEXTURE_PLUGIN(obj)                                      \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), open_dex_texture_plugin_get_type(),  \
                              OpenDexTexturePlugin))

typedef struct _OpenDexFrameTexture OpenDexFrameTexture;
typedef struct _OpenDexFrameTextureClass OpenDexFrameTextureClass;

struct _OpenDexFrameTexture {
  FlPixelBufferTexture parent_instance;
  FlTextureRegistrar* registrar;
  gchar* fifo_path;
  guint32 width;
  guint32 height;
  gsize frame_size;
  guint8* buffers[3];
  guint writing_buffer;
  guint ready_buffer;
  guint presenting_buffer;
  gboolean has_new_frame;
  GMutex mutex;
  GThread* reader;
  gint stopping;
  gint frame_count;
  gint presented_frame_count;
  gint64 last_frame_monotonic_us;
  gint center_luma;
  gint probe_luma;
  gint dropped_frames;
};

struct _OpenDexFrameTextureClass {
  FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(OpenDexFrameTexture, open_dex_frame_texture,
              fl_pixel_buffer_texture_get_type())

static gint rgba_luma(const guint8* pixel) {
  return (77 * pixel[0] + 150 * pixel[1] + 29 * pixel[2]) >> 8;
}

static gboolean open_dex_frame_texture_copy_pixels(
    FlPixelBufferTexture* texture, const uint8_t** out_buffer,
    uint32_t* width, uint32_t* height, GError** error) {
  OpenDexFrameTexture* self =
      reinterpret_cast<OpenDexFrameTexture*>(texture);
  g_mutex_lock(&self->mutex);
  if (self->has_new_frame) {
    self->presenting_buffer = self->ready_buffer;
    self->has_new_frame = FALSE;
    g_atomic_int_inc(&self->presented_frame_count);
  }
  *out_buffer = self->buffers[self->presenting_buffer];
  *width = self->width;
  *height = self->height;
  g_mutex_unlock(&self->mutex);
  return TRUE;
}

static gpointer open_dex_frame_texture_read(gpointer data) {
  OpenDexFrameTexture* self =
      reinterpret_cast<OpenDexFrameTexture*>(data);
  int fd = -1;
  gsize offset = 0;
  while (!g_atomic_int_get(&self->stopping)) {
    if (fd < 0) {
      // Texture readers stay open for the lifetime of a window. Without
      // close-on-exec, every later FFmpeg and scrcpy process inherits every
      // older frame FIFO, preventing retired pipelines from observing EOF and
      // eventually leaving blank virtual displays behind.
      fd = open(self->fifo_path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
      if (fd < 0) {
        g_usleep(5000);
        continue;
      }
      // Increasing the pipe is best-effort: older kernels or restricted
      // environments may reject it, but poll-driven draining remains correct.
      fcntl(fd, F_SETPIPE_SZ, 1048576);
    }

    pollfd descriptor = {};
    descriptor.fd = fd;
    descriptor.events = POLLIN | POLLHUP | POLLERR;
    const int poll_result = poll(&descriptor, 1, 50);
    if (poll_result < 0) {
      if (errno == EINTR) continue;
      close(fd);
      fd = -1;
      offset = 0;
      continue;
    }
    if (poll_result == 0) continue;

    gboolean reopen = FALSE;
    if (descriptor.revents & POLLIN) {
      while (!g_atomic_int_get(&self->stopping)) {
        ssize_t count =
            read(fd, self->buffers[self->writing_buffer] + offset,
                 self->frame_size - offset);
        if (count > 0) {
          offset += static_cast<gsize>(count);
          if (offset == self->frame_size) {
            const guint completed_buffer = self->writing_buffer;
            const guint8* completed = self->buffers[completed_buffer];
            const gsize center_offset =
                (static_cast<gsize>(self->height / 2) * self->width +
                 self->width / 2) *
                4;
            const guint32 probe_x = self->width > 12 ? 12 : self->width - 1;
            const guint32 probe_y = self->height > 12 ? 12 : self->height - 1;
            const gsize probe_offset =
                (static_cast<gsize>(probe_y) * self->width + probe_x) * 4;

            g_mutex_lock(&self->mutex);
            if (self->has_new_frame) self->dropped_frames += 1;
            self->ready_buffer = completed_buffer;
            self->has_new_frame = TRUE;
            for (guint candidate = 0; candidate < 3; candidate += 1) {
              if (candidate != self->presenting_buffer &&
                  candidate != self->ready_buffer) {
                self->writing_buffer = candidate;
                break;
              }
            }
            self->last_frame_monotonic_us = g_get_monotonic_time();
            self->center_luma = rgba_luma(completed + center_offset);
            self->probe_luma = rgba_luma(completed + probe_offset);
            g_atomic_int_inc(&self->frame_count);
            g_mutex_unlock(&self->mutex);

            offset = 0;
            fl_texture_registrar_mark_texture_frame_available(
                self->registrar, FL_TEXTURE(self));
          }
          continue;
        }
        if (count == 0) {
          reopen = TRUE;
        } else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
          reopen = TRUE;
        }
        break;
      }
    }
    if (descriptor.revents & (POLLHUP | POLLERR)) reopen = TRUE;
    if (reopen) {
      close(fd);
      fd = -1;
      offset = 0;
      // A FIFO with no writer reports HUP immediately. Avoid a reopen spin;
      // this delay is never used while a writer is delivering frame bytes.
      if (!g_atomic_int_get(&self->stopping)) g_usleep(5000);
    }
  }
  if (fd >= 0) close(fd);
  return nullptr;
}

static void open_dex_frame_texture_dispose(GObject* object) {
  OpenDexFrameTexture* self =
      reinterpret_cast<OpenDexFrameTexture*>(object);
  g_atomic_int_set(&self->stopping, TRUE);
  if (self->reader != nullptr) {
    g_thread_join(self->reader);
    self->reader = nullptr;
  }
  g_clear_pointer(&self->buffers[0], g_free);
  g_clear_pointer(&self->buffers[1], g_free);
  g_clear_pointer(&self->buffers[2], g_free);
  g_clear_pointer(&self->fifo_path, g_free);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(open_dex_frame_texture_parent_class)->dispose(object);
}

static void open_dex_frame_texture_class_init(
    OpenDexFrameTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = open_dex_frame_texture_dispose;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      open_dex_frame_texture_copy_pixels;
}

static void open_dex_frame_texture_init(OpenDexFrameTexture* self) {
  g_mutex_init(&self->mutex);
}

static OpenDexFrameTexture* open_dex_frame_texture_new(
    FlTextureRegistrar* registrar, const gchar* fifo_path, guint32 width,
    guint32 height) {
  OpenDexFrameTexture* self = reinterpret_cast<OpenDexFrameTexture*>(
      g_object_new(open_dex_frame_texture_get_type(), nullptr));
  self->registrar = registrar;
  self->fifo_path = g_strdup(fifo_path);
  self->width = width;
  self->height = height;
  self->frame_size = static_cast<gsize>(width) * height * 4;
  self->buffers[0] = static_cast<guint8*>(g_malloc0(self->frame_size));
  self->buffers[1] = static_cast<guint8*>(g_malloc0(self->frame_size));
  self->buffers[2] = static_cast<guint8*>(g_malloc0(self->frame_size));
  self->presenting_buffer = 0;
  self->ready_buffer = 0;
  self->writing_buffer = 1;
  self->reader =
      g_thread_new("open-dex-frame-reader", open_dex_frame_texture_read, self);
  return self;
}

static void open_dex_frame_texture_stop(OpenDexFrameTexture* self) {
  g_atomic_int_set(&self->stopping, TRUE);
}

struct _OpenDexTexturePlugin {
  GObject parent_instance;
  FlTextureRegistrar* registrar;
  GHashTable* textures;
};

G_DEFINE_TYPE(OpenDexTexturePlugin, open_dex_texture_plugin,
              g_object_get_type())

static FlValue* map_value(FlValue* args, const gchar* key) {
  return args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(args, key)
             : nullptr;
}

static FlMethodResponse* handle_create(OpenDexTexturePlugin* self,
                                       FlMethodCall* call) {
  FlValue* args = fl_method_call_get_args(call);
  FlValue* path_value = map_value(args, "fifoPath");
  FlValue* width_value = map_value(args, "width");
  FlValue* height_value = map_value(args, "height");
  if (path_value == nullptr || width_value == nullptr ||
      height_value == nullptr ||
      fl_value_get_type(path_value) != FL_VALUE_TYPE_STRING ||
      fl_value_get_type(width_value) != FL_VALUE_TYPE_INT ||
      fl_value_get_type(height_value) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid-arguments", "Expected fifoPath, width, and height.", nullptr));
  }
  const gchar* path = fl_value_get_string(path_value);
  gint64 width = fl_value_get_int(width_value);
  gint64 height = fl_value_get_int(height_value);
  struct stat info = {};
  if (width < 1 || width > 4096 || height < 1 || height > 4096 ||
      stat(path, &info) != 0 || !S_ISFIFO(info.st_mode)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid-frame-source", "The raw frame source is not a valid FIFO.",
        nullptr));
  }
  OpenDexFrameTexture* texture = open_dex_frame_texture_new(
      self->registrar, path, static_cast<guint32>(width),
      static_cast<guint32>(height));
  if (!fl_texture_registrar_register_texture(self->registrar,
                                             FL_TEXTURE(texture))) {
    g_object_unref(texture);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "texture-registration-failed", "Could not register the video texture.",
        nullptr));
  }
  gint64 texture_id = fl_texture_get_id(FL_TEXTURE(texture));
  gint64* key = g_new(gint64, 1);
  *key = texture_id;
  g_hash_table_insert(self->textures, key, texture);
  g_autoptr(FlValue) result = fl_value_new_int(texture_id);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_close(OpenDexTexturePlugin* self,
                                      FlMethodCall* call) {
  FlValue* id_value = map_value(fl_method_call_get_args(call), "textureId");
  if (id_value == nullptr || fl_value_get_type(id_value) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid-arguments", "Expected textureId.", nullptr));
  }
  gint64 texture_id = fl_value_get_int(id_value);
  OpenDexFrameTexture* texture = reinterpret_cast<OpenDexFrameTexture*>(
      g_hash_table_lookup(self->textures, &texture_id));
  if (texture != nullptr) {
    open_dex_frame_texture_stop(texture);
    fl_texture_registrar_unregister_texture(self->registrar,
                                            FL_TEXTURE(texture));
    g_hash_table_remove(self->textures, &texture_id);
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* handle_frame_count(OpenDexTexturePlugin* self,
                                            FlMethodCall* call) {
  FlValue* id_value = map_value(fl_method_call_get_args(call), "textureId");
  if (id_value == nullptr || fl_value_get_type(id_value) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid-arguments", "Expected textureId.", nullptr));
  }
  gint64 texture_id = fl_value_get_int(id_value);
  OpenDexFrameTexture* texture = reinterpret_cast<OpenDexFrameTexture*>(
      g_hash_table_lookup(self->textures, &texture_id));
  if (texture == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "texture-not-found", "That video texture has closed.", nullptr));
  }
  g_autoptr(FlValue) result =
      fl_value_new_int(g_atomic_int_get(&texture->frame_count));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_stats(OpenDexTexturePlugin* self,
                                      FlMethodCall* call) {
  FlValue* id_value = map_value(fl_method_call_get_args(call), "textureId");
  if (id_value == nullptr || fl_value_get_type(id_value) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid-arguments", "Expected textureId.", nullptr));
  }
  gint64 texture_id = fl_value_get_int(id_value);
  OpenDexFrameTexture* texture = reinterpret_cast<OpenDexFrameTexture*>(
      g_hash_table_lookup(self->textures, &texture_id));
  if (texture == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "texture-not-found", "That video texture has closed.", nullptr));
  }

  gint64 last_frame_monotonic_us;
  gint center_luma;
  gint probe_luma;
  gint dropped_frames;
  gint frames;
  gint presented_frames;
  g_mutex_lock(&texture->mutex);
  frames = g_atomic_int_get(&texture->frame_count);
  presented_frames = g_atomic_int_get(&texture->presented_frame_count);
  last_frame_monotonic_us = texture->last_frame_monotonic_us;
  center_luma = texture->center_luma;
  probe_luma = texture->probe_luma;
  dropped_frames = texture->dropped_frames;
  g_mutex_unlock(&texture->mutex);

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "frames", fl_value_new_int(frames));
  fl_value_set_string_take(result, "presentedFrames",
                           fl_value_new_int(presented_frames));
  fl_value_set_string_take(result, "lastFrameMonotonicUs",
                           fl_value_new_int(last_frame_monotonic_us));
  fl_value_set_string_take(result, "centerLuma",
                           fl_value_new_int(center_luma));
  fl_value_set_string_take(result, "probeLuma",
                           fl_value_new_int(probe_luma));
  fl_value_set_string_take(result, "droppedFrames",
                           fl_value_new_int(dropped_frames));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  OpenDexTexturePlugin* self = OPEN_DEX_TEXTURE_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_str_equal(method, "create")) {
    response = handle_create(self, call);
  } else if (g_str_equal(method, "close")) {
    response = handle_close(self, call);
  } else if (g_str_equal(method, "frameCount")) {
    response = handle_frame_count(self, call);
  } else if (g_str_equal(method, "stats")) {
    response = handle_stats(self, call);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static void unregister_texture(gpointer key, gpointer value,
                               gpointer user_data) {
  FlTextureRegistrar* registrar = FL_TEXTURE_REGISTRAR(user_data);
  OpenDexFrameTexture* texture =
      reinterpret_cast<OpenDexFrameTexture*>(value);
  open_dex_frame_texture_stop(texture);
  fl_texture_registrar_unregister_texture(
      registrar, FL_TEXTURE(texture));
}

static void open_dex_texture_plugin_dispose(GObject* object) {
  OpenDexTexturePlugin* self = OPEN_DEX_TEXTURE_PLUGIN(object);
  if (self->textures != nullptr) {
    g_hash_table_foreach(self->textures, unregister_texture, self->registrar);
    g_clear_pointer(&self->textures, g_hash_table_unref);
  }
  g_clear_object(&self->registrar);
  G_OBJECT_CLASS(open_dex_texture_plugin_parent_class)->dispose(object);
}

static void open_dex_texture_plugin_class_init(
    OpenDexTexturePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = open_dex_texture_plugin_dispose;
}

static void open_dex_texture_plugin_init(OpenDexTexturePlugin* self) {
  self->textures = g_hash_table_new_full(g_int64_hash, g_int64_equal, g_free,
                                         g_object_unref);
}

void open_dex_texture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  signal(SIGPIPE, SIG_IGN);
  OpenDexTexturePlugin* plugin = OPEN_DEX_TEXTURE_PLUGIN(
      g_object_new(open_dex_texture_plugin_get_type(), nullptr));
  plugin->registrar =
      FL_TEXTURE_REGISTRAR(g_object_ref(fl_plugin_registrar_get_texture_registrar(
          registrar)));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "open_dex_texture",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);
  g_object_unref(plugin);
}
