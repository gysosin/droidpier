#include "include/open_dex_texture/open_dex_texture_plugin_c_api.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;

class FrameTexture {
 public:
  FrameTexture(flutter::TextureRegistrar* registrar, size_t width, size_t height,
               const std::wstring& path)
      : registrar_(registrar), width_(width), height_(height), size_(width * height * 4),
        texture_(flutter::PixelBufferTexture([this](size_t, size_t) { return Pixels(); })) {
    for (auto& buffer : buffers_) buffer.resize(size_);
    pixel_.width = width;
    pixel_.height = height;
    pipe_ = CreateNamedPipeW(path.c_str(), PIPE_ACCESS_INBOUND | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT | PIPE_REJECT_REMOTE_CLIENTS,
        1, 0, 1024 * 1024, 0, nullptr);
  }
  ~FrameTexture() { Stop(); if (pipe_ != INVALID_HANDLE_VALUE) CloseHandle(pipe_); }
  bool Start() {
    if (pipe_ == INVALID_HANDLE_VALUE) return false;
    id = registrar_->RegisterTexture(&texture_);
    if (id < 0) return false;
    reader_ = std::thread([this] { Read(); });
    return true;
  }
  void Stop() {
    stopping_ = true;
    if (reader_.joinable()) reader_.join();
  }
  EncodableMap Stats() {
    std::lock_guard<std::mutex> lock(mutex_);
    return {{EncodableValue("frames"), EncodableValue(frames_)},
      {EncodableValue("presentedFrames"), EncodableValue(presented_)},
      {EncodableValue("lastFrameMonotonicUs"), EncodableValue(last_)},
      {EncodableValue("centerLuma"), EncodableValue(center_)},
      {EncodableValue("probeLuma"), EncodableValue(probe_)},
      {EncodableValue("droppedFrames"), EncodableValue(dropped_)}};
  }
  int64_t id = -1;

 private:
  const FlutterDesktopPixelBuffer* Pixels() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (ready_frame_) { presenting_ = ready_; ready_frame_ = false; ++presented_; }
    pixel_.buffer = buffers_[presenting_].data();
    return &pixel_;
  }
  int64_t Luma(const uint8_t* p) { return (77 * p[0] + 150 * p[1] + 29 * p[2]) >> 8; }
  void Read() {
    size_t offset = 0;
    while (!stopping_) {
      ConnectNamedPipe(pipe_, nullptr);
      DWORD count = 0;
      const BOOL read = ReadFile(pipe_, buffers_[writing_].data() + offset,
          static_cast<DWORD>(size_ - offset), &count, nullptr);
      if (read && count > 0) {
        offset += count;
        if (offset == size_) {
          {
            std::lock_guard<std::mutex> lock(mutex_);
            const auto* data = buffers_[writing_].data();
            center_ = Luma(data + ((height_ / 2) * width_ + width_ / 2) * 4);
            const size_t x = width_ > 12 ? 12 : width_ - 1;
            const size_t y = height_ > 12 ? 12 : height_ - 1;
            probe_ = Luma(data + (y * width_ + x) * 4);
            if (ready_frame_) ++dropped_;
            ready_ = writing_;
            ready_frame_ = true;
            for (size_t i = 0; i < 3; ++i) {
              if (i != ready_ && i != presenting_) { writing_ = i; break; }
            }
            ++frames_;
            last_ = std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
          }
          offset = 0;
          registrar_->MarkTextureFrameAvailable(id);
        }
      } else {
        const DWORD error = GetLastError();
        if (error == ERROR_BROKEN_PIPE) { DisconnectNamedPipe(pipe_); offset = 0; }
        Sleep(5);
      }
    }
  }
  flutter::TextureRegistrar* registrar_;
  size_t width_, height_, size_;
  flutter::TextureVariant texture_;
  FlutterDesktopPixelBuffer pixel_ = {};
  HANDLE pipe_ = INVALID_HANDLE_VALUE;
  std::thread reader_;
  std::atomic<bool> stopping_{false};
  std::mutex mutex_;
  std::array<std::vector<uint8_t>, 3> buffers_;
  size_t writing_ = 1, ready_ = 0, presenting_ = 0;
  bool ready_frame_ = false;
  int64_t frames_ = 0, presented_ = 0, last_ = 0, center_ = 0, probe_ = 0, dropped_ = 0;
};

class TexturePlugin : public flutter::Plugin {
 public:
  explicit TexturePlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar->texture_registrar()), channel_(registrar->messenger(),
            "open_dex_texture", &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) { Handle(call, std::move(result)); });
  }
  ~TexturePlugin() override {
    channel_.SetMethodCallHandler(nullptr);
    while (!frames_.empty()) Close(frames_.begin()->first);
  }

 private:
  static const EncodableValue* Value(const EncodableMap& args, const char* name) {
    const auto found = args.find(EncodableValue(name));
    return found == args.end() ? nullptr : &found->second;
  }
  static int64_t Integer(const EncodableValue* value) {
    if (!value) return -1;
    if (auto v = std::get_if<int32_t>(value)) return *v;
    if (auto v = std::get_if<int64_t>(value)) return *v;
    return -1;
  }
  void Close(int64_t id) {
    const auto it = frames_.find(id);
    if (it == frames_.end()) return;
    auto frame = it->second;
    frame->Stop();
    frames_.erase(it);
    registrar_->UnregisterTexture(id, [frame] {});
  }
  void Handle(const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
    if (!args) { result->Error("invalid-arguments", "Expected an argument map."); return; }
    if (call.method_name() == "create") {
      const auto width = Integer(Value(*args, "width"));
      const auto height = Integer(Value(*args, "height"));
      const auto* path_value = Value(*args, "fifoPath");
      const auto* path = path_value ? std::get_if<std::string>(path_value) : nullptr;
      if (!path || path->rfind("\\\\.\\pipe\\droidpier-", 0) != 0 ||
          width < 1 || width > 4096 || height < 1 || height > 4096) {
        result->Error("invalid-frame-source", "Expected a local frame pipe and valid dimensions."); return;
      }
      const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(), static_cast<int>(path->size()), nullptr, 0);
      if (length == 0) { result->Error("invalid-frame-source", "Invalid pipe name."); return; }
      std::wstring wide(static_cast<size_t>(length), L'\0');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(), static_cast<int>(path->size()), wide.data(), length);
      auto frame = std::make_shared<FrameTexture>(registrar_, static_cast<size_t>(width), static_cast<size_t>(height), wide);
      if (!frame->Start()) { result->Error("texture-registration-failed", "Could not create video texture."); return; }
      frames_[frame->id] = frame;
      result->Success(EncodableValue(frame->id));
      return;
    }
    const auto id = Integer(Value(*args, "textureId"));
    if (call.method_name() == "close") { Close(id); result->Success(); return; }
    const auto it = frames_.find(id);
    if (it == frames_.end()) { result->Error("texture-not-found", "That video texture has closed."); return; }
    const auto stats = it->second->Stats();
    if (call.method_name() == "stats") result->Success(EncodableValue(stats));
    else if (call.method_name() == "frameCount") result->Success(stats.at(EncodableValue("frames")));
    else result->NotImplemented();
  }
  flutter::TextureRegistrar* registrar_;
  flutter::MethodChannel<EncodableValue> channel_;
  std::map<int64_t, std::shared_ptr<FrameTexture>> frames_;
};
}  // namespace

void OpenDexTexturePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* plugin_registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  plugin_registrar->AddPlugin(std::make_unique<TexturePlugin>(plugin_registrar));
}
