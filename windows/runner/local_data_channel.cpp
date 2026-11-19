#include "local_data_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shlobj.h>
#include <string>

namespace {
constexpr char kLocalDataChannelName[] = "blackgrid/local_data";

std::string Utf8(const wchar_t* text) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0,
      nullptr, nullptr);
  if (size <= 1) return {};
  std::string value(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, value.data(), size, nullptr, nullptr);
  value.resize(size - 1);
  return value;
}
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterLocalDataChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kLocalDataChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "localDataPath") {
      result->NotImplemented();
      return;
    }
    PWSTR path = nullptr;
    const HRESULT status = SHGetKnownFolderPath(FOLDERID_LocalAppData, 0,
        nullptr, &path);
    if (FAILED(status) || path == nullptr) {
      result->Error("unavailable", "Local application data is unavailable.");
      return;
    }
    const auto value = Utf8(path);
    CoTaskMemFree(path);
    result->Success(flutter::EncodableValue(value));
  });
  return channel;
}
