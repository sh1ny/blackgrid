// Window snapshots, process names and desktop-GDI capture (design D3, D6).
// Native code reports facts; Dart decides. No other process is ever opened:
// executable names come from a toolhelp listing only.
#include "capture_internal.h"

#include <tlhelp32.h>

namespace bgc {

namespace {

void fill_rect(bgc_rect* out, LONG left, LONG top, LONG right, LONG bottom) {
  out->left = left;
  out->top = top;
  out->width = right - left;
  out->height = bottom - top;
}

}  // namespace

bool list_processes_real(std::vector<ProcessEntry>* out, DWORD* win32_error) {
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) {
    *win32_error = GetLastError();
    return false;
  }
  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  bool ok = true;
  if (Process32FirstW(snap, &entry)) {
    do {
      ProcessEntry item;
      item.pid = entry.th32ProcessID;
      item.exe = entry.szExeFile;
      out->push_back(item);
    } while (Process32NextW(snap, &entry));
  } else {
    *win32_error = GetLastError();
    ok = false;
  }
  CloseHandle(snap);
  return ok;
}

int32_t exe_name_lookup(const std::vector<ProcessEntry>& listing, uint32_t pid,
                        uint16_t* name, uint32_t capacity_chars) {
  for (const ProcessEntry& entry : listing) {
    if (entry.pid != pid) continue;
    if (name == nullptr || entry.exe.size() + 1 > capacity_chars) {
      return BGC_CAPTURE_FAILED;
    }
    for (size_t i = 0; i < entry.exe.size(); i++) {
      name[i] = static_cast<uint16_t>(entry.exe[i]);
    }
    name[entry.exe.size()] = 0;
    return BGC_OK;
  }
  return BGC_NOT_FOUND;
}

bool listing_has_game(const std::vector<ProcessEntry>& listing,
                      std::wstring* which) {
  static const wchar_t* const kGameExecutables[] = {
      L"EscapeFromTarkov.exe", L"EscapeFromTarkov_BE.exe"};
  for (const ProcessEntry& entry : listing) {
    for (const wchar_t* game : kGameExecutables) {
      if (_wcsicmp(entry.exe.c_str(), game) == 0) {
        if (which != nullptr) *which = game;
        return true;
      }
    }
  }
  return false;
}

}  // namespace bgc

namespace {

using namespace bgc;

int32_t snapshot_window(uint64_t hwnd_value, bgc_window_snapshot* out) {
  memset(out, 0, sizeof(*out));
  HWND hwnd = reinterpret_cast<HWND>(static_cast<uintptr_t>(hwnd_value));
  if (hwnd_value == 0 || !IsWindow(hwnd)) return BGC_TARGET_GONE;
  DWORD pid = 0;
  DWORD tid = GetWindowThreadProcessId(hwnd, &pid);
  if (tid == 0) return BGC_TARGET_GONE;  // destroyed between the two calls

  bgc_window_snapshot snap = {};
  snap.hwnd = hwnd_value;
  snap.pid = pid;
  snap.tid = tid;
  snap.minimised = IsIconic(hwnd) ? 1 : 0;
  snap.foreground = GetForegroundWindow() == hwnd ? 1 : 0;
  snap.dpi = GetDpiForWindow(hwnd);

  RECT client = {};
  POINT origin = {0, 0};
  if (GetClientRect(hwnd, &client) && ClientToScreen(hwnd, &origin)) {
    fill_rect(&snap.client, origin.x, origin.y, origin.x + client.right,
              origin.y + client.bottom);
  } else if (!IsWindow(hwnd)) {
    return BGC_TARGET_GONE;
  }

  MONITORINFO monitor = {};
  monitor.cbSize = sizeof(monitor);
  HMONITOR handle = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (handle != nullptr && GetMonitorInfoW(handle, &monitor)) {
    fill_rect(&snap.monitor, monitor.rcMonitor.left, monitor.rcMonitor.top,
              monitor.rcMonitor.right, monitor.rcMonitor.bottom);
  }

  snap.virtual_desktop.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  snap.virtual_desktop.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  snap.virtual_desktop.width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  snap.virtual_desktop.height = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  // InternalGetWindowText never sends a window message.
  wchar_t title[BGC_TITLE_CHARS] = {};
  InternalGetWindowText(hwnd, title, BGC_TITLE_CHARS);
  title[BGC_TITLE_CHARS - 1] = 0;
  for (int i = 0; i < BGC_TITLE_CHARS; i++) {
    snap.title[i] = static_cast<uint16_t>(title[i]);
    if (title[i] == 0) break;
  }
  *out = snap;
  return BGC_OK;
}

}  // namespace

BGC_API uint32_t bgc_abi(void) { return BGC_ABI_VERSION; }

BGC_API int32_t bgc_snapshot(uint64_t hwnd, bgc_window_snapshot* out) {
  if (out == nullptr) return BGC_INVALID_ARGUMENT;
  return snapshot_window(hwnd, out);
}

BGC_API int32_t bgc_process_name(uint32_t pid, uint16_t* name,
                                 uint32_t capacity_chars) {
  if (name == nullptr || capacity_chars == 0) return BGC_INVALID_ARGUMENT;
  std::vector<ProcessEntry> listing;
  DWORD error = 0;
  if (!list_processes_real(&listing, &error)) return BGC_CAPTURE_FAILED;
  return exe_name_lookup(listing, pid, name, capacity_chars);
}

BGC_API int32_t bgc_capture(uint64_t hwnd, const bgc_rect* rect,
                            bgc_capture_result* out) {
  if (rect == nullptr || out == nullptr) return BGC_INVALID_ARGUMENT;
  memset(out, 0, sizeof(*out));
  if (rect->width < 1 || rect->height < 1 || rect->width > BGC_MAX_SIDE ||
      rect->height > BGC_MAX_SIDE ||
      static_cast<int64_t>(rect->width) * rect->height > BGC_MAX_PIXELS) {
    return BGC_INVALID_ARGUMENT;
  }

  Registry& reg = global_registry();
  uint64_t id = registry_reserve(reg);
  if (id == 0) return BGC_FRAME_BUDGET;
  // Any failure below frees the slot here, natively.
  auto fail = [&](int32_t status, DWORD error) {
    registry_release(reg, id);
    out->frame_id = 0;
    out->win32_error = error;
    return status;
  };

  int32_t pre = snapshot_window(hwnd, &out->pre);
  if (pre != BGC_OK) return fail(pre, 0);

  DWORD error = 0;
  if (!registry_allocate(reg, id, rect->width, rect->height, &error)) {
    return fail(BGC_CAPTURE_FAILED, error);
  }
  bgc_frame_view view = {};
  HBITMAP bitmap = nullptr;
  if (!registry_info(reg, id, &view, &bitmap)) {
    return fail(BGC_CAPTURE_FAILED, ERROR_INVALID_HANDLE);
  }

  HDC screen = GetDC(nullptr);
  if (screen == nullptr) return fail(BGC_CAPTURE_FAILED, GetLastError());
  HDC memory = CreateCompatibleDC(screen);
  if (memory == nullptr) {
    DWORD e = GetLastError();
    ReleaseDC(nullptr, screen);
    return fail(BGC_CAPTURE_FAILED, e);
  }
  HGDIOBJ previous = SelectObject(memory, bitmap);
  if (previous == nullptr || previous == HGDI_ERROR) {
    DWORD e = GetLastError();
    DeleteDC(memory);
    ReleaseDC(nullptr, screen);
    return fail(BGC_CAPTURE_FAILED, e);
  }

  LARGE_INTEGER before, after;
  QueryPerformanceCounter(&before);
  BOOL blitted = BitBlt(memory, 0, 0, rect->width, rect->height, screen,
                        rect->left, rect->top, SRCCOPY);
  DWORD blit_error = blitted ? 0 : GetLastError();
  QueryPerformanceCounter(&after);

  SelectObject(memory, previous);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  if (!blitted) {
    return fail(BGC_CAPTURE_FAILED, blit_error != 0 ? blit_error : ERROR_GEN_FAILURE);
  }

  int32_t post = snapshot_window(hwnd, &out->post);
  if (post != BGC_OK) return fail(post, 0);

  out->qpc_before = before.QuadPart;
  out->qpc_after = after.QuadPart;
  out->all_zero = bgr_all_zero(view.pixels, view.width, view.height, view.stride) ? 1 : 0;
  out->frame_id = id;
  out->win32_error = 0;
  return BGC_OK;
}

BGC_API int32_t bgc_frame_info(uint64_t frame_id, bgc_frame_view* out) {
  if (out == nullptr) return BGC_INVALID_ARGUMENT;
  if (!bgc::registry_info(bgc::global_registry(), frame_id, out)) {
    memset(out, 0, sizeof(*out));
    return BGC_FRAME_RELEASED;
  }
  return BGC_OK;
}

BGC_API void bgc_frame_release(uint64_t frame_id) {
  bgc::registry_release(bgc::global_registry(), frame_id);
}

BGC_API uint32_t bgc_frame_live_count(void) {
  return bgc::registry_live_count(bgc::global_registry());
}

BGC_API void bgc_frame_finalize(void* token) {
  bgc_frame_release(static_cast<uint64_t>(reinterpret_cast<uintptr_t>(token)));
}

BGC_API int64_t bgc_qpc_now(void) {
  LARGE_INTEGER v;
  QueryPerformanceCounter(&v);
  return v.QuadPart;
}

BGC_API int64_t bgc_qpc_frequency(void) {
  LARGE_INTEGER v;
  QueryPerformanceFrequency(&v);
  return v.QuadPart;
}
