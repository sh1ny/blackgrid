#include "recycle_channel.h"

#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <climits>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <utility>
#include <system_error>
#include <vector>
#include <variant>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResultPtr = std::unique_ptr<flutter::MethodResult<EncodableValue>>;
using Microsoft::WRL::ComPtr;

constexpr char kChannelName[] = "blackgrid/recycle";
std::atomic<uint64_t> next_generation{0};

struct Entry {
  std::string name;
  const char* status = "cancelled";
};

// The worker owns only this state, never the channel or messenger.
struct Shared {
  std::mutex mutex;
  HWND window = nullptr;
  uint64_t generation = 0;
  std::atomic<bool> stop{false};
  std::vector<Entry> entries;
};

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

bool Wide(const std::string& text, std::wstring* result) {
  if (text.empty() || text.find('\0') != std::string::npos ||
      text.size() > static_cast<size_t>(INT_MAX)) return false;
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (count == 0) return false;
  result->resize(count);
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
      static_cast<int>(text.size()), result->data(), count) == count;
}

bool ValidName(const std::wstring& name) {
  if (name.empty() || name.find(L"..") != std::wstring::npos ||
      name.back() == L'.' || name.back() == L' ') return false;
  for (wchar_t c : name) {
    if (c < 32 || c == L'/' || c == L'\\' || c == L':' || c == L'*' ||
        c == L'?' || c == L'"' || c == L'<' || c == L'>' || c == L'|') {
      return false;
    }
  }
  const size_t dot = name.find(L'.');
  std::wstring device = name.substr(0, dot);
  for (auto& c : device) {
    if (c >= L'a' && c <= L'z') c -= L'a' - L'A';
  }
  if (device == L"CON" || device == L"PRN" || device == L"AUX" ||
      device == L"NUL" || device == L"CONIN$" || device == L"CONOUT$") {
    return false;
  }
  if (device.size() == 4 &&
      (device.compare(0, 3, L"COM") == 0 || device.compare(0, 3, L"LPT") == 0) &&
      ((device[3] >= L'1' && device[3] <= L'9') || device[3] == L'\u00b9' ||
       device[3] == L'\u00b2' || device[3] == L'\u00b3')) return false;
  return true;
}

bool AbsoluteFolder(const std::wstring& folder) {
  // Drive-absolute and UNC paths only; reject device namespace paths.
  if (folder.size() >= 3 &&
      ((folder[0] >= L'A' && folder[0] <= L'Z') ||
       (folder[0] >= L'a' && folder[0] <= L'z')) &&
      folder[1] == L':' && (folder[2] == L'\\' || folder[2] == L'/')) {
    return true;
  }
  return folder.size() >= 5 && folder[0] == L'\\' && folder[1] == L'\\' &&
      folder[2] != L'?' && folder[2] != L'.' && folder[2] != L'\\';
}

class DeleteSink final : public IFileOperationProgressSink {
 public:
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
    if (!out) return E_POINTER;
    *out = nullptr;
    if (iid == IID_IUnknown || iid == IID_IFileOperationProgressSink) {
      *out = static_cast<IFileOperationProgressSink*>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = --references_;
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE StartOperations() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE FinishOperations(HRESULT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PreRenameItem(DWORD, IShellItem*, LPCWSTR) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE PostRenameItem(DWORD, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE PreMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE PostMoveItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE PreCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE PostCopyItem(DWORD, IShellItem*, IShellItem*, LPCWSTR, HRESULT, IShellItem*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE PreDeleteItem(DWORD flags, IShellItem*) override {
    if (!(flags & TSF_DELETE_RECYCLE_IF_POSSIBLE)) {
      vetoed = true;
      return E_ABORT;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PostDeleteItem(DWORD, IShellItem*, HRESULT result,
                                            IShellItem* recycled) override {
    moved = SUCCEEDED(result) && recycled != nullptr;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE PreNewItem(DWORD, IShellItem*, LPCWSTR) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE PostNewItem(DWORD, IShellItem*, LPCWSTR, LPCWSTR,
                                         DWORD, HRESULT, IShellItem*) override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE UpdateProgress(UINT, UINT) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResetTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE PauseTimer() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE ResumeTimer() override { return S_OK; }

  bool vetoed = false;
  bool moved = false;

 private:
  std::atomic<ULONG> references_{1};
};

const char* RecycleOne(const std::wstring& folder, const std::string& name) {
  std::wstring wide_name;
  if (!Wide(name, &wide_name) || !ValidName(wide_name)) return "rejected";
  std::wstring path = folder;
  if (path.back() != L'\\' && path.back() != L'/') path.push_back(L'\\');
  path.append(wide_name);
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = GetLastError();
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
        ? "missing" : "failed";
  }
  if (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) {
    return "rejected";
  }
  ComPtr<IShellItem> item;
  HRESULT hr = SHCreateItemFromParsingName(path.c_str(), nullptr,
                                           IID_PPV_ARGS(&item));
  if (FAILED(hr)) {
    return hr == HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND) ||
                   hr == HRESULT_FROM_WIN32(ERROR_PATH_NOT_FOUND)
        ? "missing" : "failed";
  }
  ComPtr<IFileOperation> operation;
  hr = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_ALL,
                        IID_PPV_ARGS(&operation));
  if (FAILED(hr)) return "failed";
  hr = operation->SetOperationFlags(FOFX_RECYCLEONDELETE | FOF_ALLOWUNDO | FOF_NO_UI);
  if (FAILED(hr)) return "failed";
  ComPtr<DeleteSink> sink;
  sink.Attach(new DeleteSink());
  hr = operation->DeleteItem(item.Get(), sink.Get());
  if (FAILED(hr)) return "failed";
  hr = operation->PerformOperations();
  if (sink->vetoed) return "notRecyclable";
  if (SUCCEEDED(hr) && sink->moved) return "moved";
  return "failed";
}

void Run(std::shared_ptr<Shared> shared, std::wstring folder) {
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  for (size_t i = 0; i < shared->entries.size(); ++i) {
    if (shared->stop.load()) break;
    const char* status = SUCCEEDED(initialized)
        ? RecycleOne(folder, shared->entries[i].name) : "failed";
    std::lock_guard<std::mutex> lock(shared->mutex);
    shared->entries[i].status = status;
  }
  if (SUCCEEDED(initialized)) CoUninitialize();
  std::lock_guard<std::mutex> lock(shared->mutex);
  if (shared->window) {
    PostMessage(shared->window, kRecycleChannelMessage,
                static_cast<WPARAM>(shared->generation), 0);
  }
}

EncodableValue Reply(const std::vector<Entry>& entries) {
  EncodableList list;
  list.reserve(entries.size());
  for (const auto& entry : entries) {
    EncodableMap row;
    row[EncodableValue("name")] = EncodableValue(entry.name);
    row[EncodableValue("status")] = EncodableValue(entry.status);
    list.emplace_back(std::move(row));
  }
  return EncodableValue(std::move(list));
}

}  // namespace

struct RecycleChannel::Impl {
  Impl(flutter::BinaryMessenger* messenger, HWND window_handle)
      : window(window_handle),
        channel(std::make_unique<flutter::MethodChannel<EncodableValue>>(
            messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance())) {
    channel->SetMethodCallHandler(
        [this](const flutter::MethodCall<EncodableValue>& call, MethodResultPtr result) {
          Handle(call, std::move(result));
        });
  }

  ~Impl() {
    channel->SetMethodCallHandler(nullptr);
    if (shared) {
      shared->stop = true;
      std::lock_guard<std::mutex> lock(shared->mutex);
      shared->window = nullptr;
      if (pending) {
        for (auto& entry : shared->entries) entry.status = "cancelled";
        pending->Success(Reply(shared->entries));
        pending.reset();
      }
    }
  }

  void Handle(const flutter::MethodCall<EncodableValue>& call, MethodResultPtr result) {
    if (call.method_name() == "cancel") {
      if (call.arguments() && !std::holds_alternative<std::monostate>(*call.arguments())) {
        result->Error("bad_arguments", "Cancel takes no arguments.");
        return;
      }
      if (shared) shared->stop = true;
      result->Success();
      return;
    }
    if (call.method_name() != "recycle") {
      result->NotImplemented();
      return;
    }
    if (pending) {
      result->Error("busy", "A recycle call is already pending.");
      return;
    }
    const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
    const auto* folder_value = args ? Find(*args, "folder") : nullptr;
    const auto* names_value = args ? Find(*args, "names") : nullptr;
    const auto* folder = folder_value ? std::get_if<std::string>(folder_value) : nullptr;
    const auto* names = names_value ? std::get_if<EncodableList>(names_value) : nullptr;
    std::wstring wide_folder;
    if (!folder || !names || names->size() > 64 || !Wide(*folder, &wide_folder) ||
        !AbsoluteFolder(wide_folder)) {
      result->Error("bad_arguments", "Expected an absolute folder and at most 64 names.");
      return;
    }
    // Dart directory paths may mix separators; Shell parsing requires Windows ones.
    for (auto& character : wide_folder) {
      if (character == L'/') character = L'\\';
    }
    auto next = std::make_shared<Shared>();
    next->window = window;
    next->generation = ++next_generation;
    next->entries.reserve(names->size());
    std::unordered_set<std::string> seen;
    for (const auto& value : *names) {
      const auto* name = std::get_if<std::string>(&value);
      if (!name || !seen.insert(*name).second) {
        result->Error("bad_arguments", "Names must be distinct strings.");
        return;
      }
      next->entries.push_back({*name});
    }
    shared = std::move(next);
    pending = std::move(result);
    try {
      std::thread(Run, shared, std::move(wide_folder)).detach();
    } catch (const std::system_error&) {
      shared.reset();
      pending->Error("unavailable", "Could not start the recycle worker.");
      pending.reset();
    }
  }

  void OnMessage(WPARAM generation) {
    if (!pending || !shared ||
        generation != static_cast<WPARAM>(shared->generation)) return;
    auto completed = std::move(shared);
    std::lock_guard<std::mutex> lock(completed->mutex);
    pending->Success(Reply(completed->entries));
    pending.reset();
    completed->window = nullptr;
  }

  HWND window;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  std::shared_ptr<Shared> shared;
  MethodResultPtr pending;
};

RecycleChannel::RecycleChannel(flutter::BinaryMessenger* messenger, HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}
RecycleChannel::~RecycleChannel() = default;
void RecycleChannel::HandleMessage(WPARAM generation) { impl_->OnMessage(generation); }
std::unique_ptr<RecycleChannel> RegisterRecycleChannel(
    flutter::BinaryMessenger* messenger, HWND window) {
  return std::make_unique<RecycleChannel>(messenger, window);
}
