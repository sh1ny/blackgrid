#include "credential_protector.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincrypt.h>
#include <shlobj.h>
#include <limits>
#include <string>
#include <vector>

namespace {
std::wstring Wide(const std::string& text) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring value(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), value.data(), size);
  return value;
}
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
RegisterCredentialProtector(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "blackgrid/credentials",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "localDataPath") {
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
      return;
    }
    if (method == "atomicReplace") {
      const auto* values = call.arguments()
          ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      if (!values) {
        result->Error("invalid", "Invalid replacement request.");
        return;
      }
      const auto source = values->find(flutter::EncodableValue("source"));
      const auto target = values->find(flutter::EncodableValue("target"));
      if (source == values->end() || target == values->end() ||
          !std::holds_alternative<std::string>(source->second) ||
          !std::holds_alternative<std::string>(target->second)) {
        result->Error("invalid", "Invalid replacement paths.");
        return;
      }
      const auto from = Wide(std::get<std::string>(source->second));
      const auto to = Wide(std::get<std::string>(target->second));
      if (from.empty() || to.empty() ||
          !MoveFileExW(from.c_str(), to.c_str(),
              MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        result->Error("unavailable", "Protected credential replacement failed.");
        return;
      }
      result->Success();
      return;
    }
    if (method != "protect" && method != "unprotect") {
      result->NotImplemented();
      return;
    }
    const auto* bytes = call.arguments()
        ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
    if (!bytes || bytes->empty() ||
        bytes->size() > std::numeric_limits<DWORD>::max()) {
      result->Error("invalid", "Invalid protected credential bytes.");
      return;
    }
    DATA_BLOB input{static_cast<DWORD>(bytes->size()),
        const_cast<BYTE*>(bytes->data())};
    DATA_BLOB output{};
    const BOOL ok = method == "protect"
        ? CryptProtectData(&input, nullptr, nullptr, nullptr, nullptr,
            CRYPTPROTECT_UI_FORBIDDEN, &output)
        : CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
            CRYPTPROTECT_UI_FORBIDDEN, &output);
    if (!ok) {
      result->Error("unavailable", "Current-user credential protection failed.");
      return;
    }
    std::vector<uint8_t> value(output.pbData, output.pbData + output.cbData);
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    result->Success(flutter::EncodableValue(value));
    SecureZeroMemory(value.data(), value.size());
  });
  return channel;
}
