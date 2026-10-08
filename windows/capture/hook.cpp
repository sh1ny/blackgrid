// Trigger hook (design D2): one dedicated thread owns WH_MOUSE_LL and a message
// loop. The callback only filters, appends to a bounded ring and requests one
// coalesced wake-up; Dart drains the ring from its own isolate.
#include <atomic>

#include "capture_internal.h"

namespace bgc {

// --- Filter ------------------------------------------------------------------------

bool hook_filter_accepts(int nCode, WPARAM msg, HWND foreground,
                         uint32_t foreground_pid, uint32_t own_pid,
                         TitleReaderFn read_title, void* title_ctx,
                         const wchar_t* target_title) {
  if (nCode < 0 || msg != WM_LBUTTONUP) return false;
  if (foreground == nullptr || foreground_pid == 0) return false;
  // Our own windows are never read: the title read must not touch a UI thread
  // that may be blocked.
  if (foreground_pid == own_pid) return false;
  if (read_title == nullptr || target_title == nullptr ||
      target_title[0] == 0) {
    return false;
  }
  wchar_t title[BGC_TITLE_CHARS] = {};
  if (!read_title(title_ctx, foreground, title, BGC_TITLE_CHARS)) return false;
  title[BGC_TITLE_CHARS - 1] = 0;
  return wcscmp(title, target_title) == 0;
}

// --- Ring --------------------------------------------------------------------------

bool ring_append(Ring& ring, const bgc_trigger_event& event) {
  bool set_pending = false;
  AcquireSRWLockExclusive(&ring.lock);
  if (ring.count == BGC_RING_CAPACITY) {
    ring.head = (ring.head + 1) % BGC_RING_CAPACITY;  // drop the oldest
    ring.count--;
    ring.dropped++;
  }
  ring.slots[(ring.head + ring.count) % BGC_RING_CAPACITY] = event;
  ring.count++;
  if (!ring.signal_pending) {
    ring.signal_pending = true;
    set_pending = true;
  }
  ReleaseSRWLockExclusive(&ring.lock);
  return set_pending;
}

uint32_t ring_drain(Ring& ring, bgc_trigger_event* events, uint32_t capacity,
                    uint32_t* dropped) {
  AcquireSRWLockExclusive(&ring.lock);
  uint32_t copied = 0;
  if (events != nullptr) {
    while (copied < ring.count && copied < capacity) {
      events[copied] = ring.slots[(ring.head + copied) % BGC_RING_CAPACITY];
      copied++;
    }
  }
  uint32_t lost = ring.dropped + (ring.count - copied);
  ring.head = 0;
  ring.count = 0;
  ring.dropped = 0;
  ring.signal_pending = false;
  ReleaseSRWLockExclusive(&ring.lock);
  if (dropped != nullptr) *dropped = lost;
  return copied;
}

void ring_clear(Ring& ring) {
  AcquireSRWLockExclusive(&ring.lock);
  ring.head = 0;
  ring.count = 0;
  ring.dropped = 0;
  ring.signal_pending = false;
  ReleaseSRWLockExclusive(&ring.lock);
}

void ring_cancel_signal(Ring& ring) {
  AcquireSRWLockExclusive(&ring.lock);
  ring.signal_pending = false;
  ReleaseSRWLockExclusive(&ring.lock);
}

bool ring_signal_pending(Ring& ring) {
  AcquireSRWLockExclusive(&ring.lock);
  bool pending = ring.signal_pending;
  ReleaseSRWLockExclusive(&ring.lock);
  return pending;
}

// --- Callback core -----------------------------------------------------------------

LRESULT hook_proc_core(const HookEnv& env, Ring& ring,
                       const wchar_t* target_title, int nCode, WPARAM wParam,
                       LPARAM lParam) {
  if (nCode >= 0 && wParam == WM_LBUTTONUP && lParam != 0) {
    HWND foreground = env.foreground();
    uint32_t tid = 0;
    uint32_t pid = foreground != nullptr ? env.window_pid(foreground, &tid) : 0;
    if (hook_filter_accepts(nCode, wParam, foreground, pid, env.own_pid,
                            env.read_title, env.title_ctx, target_title)) {
      const MSLLHOOKSTRUCT* info =
          reinterpret_cast<const MSLLHOOKSTRUCT*>(lParam);
      bgc_trigger_event event = {};
      event.x = info->pt.x;
      event.y = info->pt.y;
      event.hwnd = reinterpret_cast<uint64_t>(foreground);
      event.pid = pid;
      event.tid = tid;
      event.qpc = env.qpc();
      // ring_append has left its critical section by the time it returns, so
      // the wake-up is requested outside the lock.
      if (ring_append(ring, event)) env.post_signal();
    }
  }
  return env.call_next(nCode, wParam, lParam);
}

// --- Real environment and lifecycle ------------------------------------------------

namespace {

Ring g_ring;
wchar_t g_target[BGC_TITLE_CHARS] = {};
void (*g_signal)(void) = nullptr;
std::atomic<bool> g_guard{false};
std::atomic<DWORD> g_thread_id{0};
HANDLE g_thread = nullptr;  // guarded by g_api_lock
SRWLOCK g_api_lock = SRWLOCK_INIT;

bool real_read_title(void*, HWND hwnd, wchar_t* buf, int cap) {
  // InternalGetWindowText reads the title without sending a window message.
  return InternalGetWindowText(hwnd, buf, cap) > 0;
}
HWND real_foreground() { return GetForegroundWindow(); }
uint32_t real_window_pid(HWND hwnd, uint32_t* tid) {
  DWORD pid = 0;
  *tid = GetWindowThreadProcessId(hwnd, &pid);
  return pid;
}
LRESULT real_call_next(int nCode, WPARAM wParam, LPARAM lParam) {
  return CallNextHookEx(nullptr, nCode, wParam, lParam);
}
void real_post_signal() {
  DWORD tid = g_thread_id.load();
  if (tid == 0 || !PostThreadMessageW(tid, WM_APP, 0, 0)) {
    ring_cancel_signal(g_ring);  // let the next append request a wake-up
  }
}
int64_t real_qpc() {
  LARGE_INTEGER v;
  QueryPerformanceCounter(&v);
  return v.QuadPart;
}

LRESULT CALLBACK low_level_mouse_proc(int nCode, WPARAM wParam, LPARAM lParam) {
  HookEnv env = {};
  env.foreground = real_foreground;
  env.window_pid = real_window_pid;
  env.read_title = real_read_title;
  env.title_ctx = nullptr;
  env.call_next = real_call_next;
  env.post_signal = real_post_signal;
  env.qpc = real_qpc;
  env.own_pid = GetCurrentProcessId();
  return hook_proc_core(env, g_ring, g_target, nCode, wParam, lParam);
}

HHOOK real_install(HOOKPROC proc, DWORD* error) {
  // A global hook names the module holding proc: this DLL, not the exe.
  HMODULE module = module_containing(reinterpret_cast<const void*>(proc));
  if (module == nullptr) {
    *error = GetLastError();
    return nullptr;
  }
  HHOOK hook = SetWindowsHookExW(WH_MOUSE_LL, proc, module, 0);
  if (hook == nullptr) *error = GetLastError();
  return hook;
}
void real_uninstall(HHOOK hook) { UnhookWindowsHookEx(hook); }

struct ThreadStart {
  HookInstaller installer;
  HANDLE ready;
  bool ok;
  DWORD error;
};

DWORD WINAPI hook_thread(LPVOID param) {
  ThreadStart* start = static_cast<ThreadStart*>(param);
  const HookInstaller installer = start->installer;
  HANDLE ready = start->ready;

  MSG msg;  // forces the thread's message queue into existence
  PeekMessageW(&msg, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
  g_thread_id.store(GetCurrentThreadId());

  DWORD error = 0;
  HHOOK hook = installer.install(low_level_mouse_proc, &error);
  start->ok = hook != nullptr;
  start->error = hook != nullptr ? 0 : (error != 0 ? error : ERROR_GEN_FAILURE);
  if (hook == nullptr) {
    g_thread_id.store(0);
    g_guard.store(false);
    SetEvent(ready);  // `start` belongs to the starter from here on
    return 0;
  }
  SetEvent(ready);

  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (msg.message == WM_APP) {
      void (*signal)(void) = g_signal;
      if (signal != nullptr) signal();
    }
  }
  installer.uninstall(hook);
  g_thread_id.store(0);
  // A thread that ends late (after a stop timed out) releases the guard here.
  g_guard.store(false);
  return 0;
}

}  // namespace

HMODULE module_containing(const void* address) {
  if (address == nullptr) return nullptr;
  HMODULE module = nullptr;
  // UNCHANGED_REFCOUNT: the module is this code's own image, already loaded.
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          static_cast<LPCWSTR>(address), &module)) {
    return nullptr;
  }
  return module;
}

const HookInstaller& hook_real_installer() {
  static const HookInstaller installer = {real_install, real_uninstall};
  return installer;
}

bool hook_guard_held() { return g_guard.load(); }

int32_t hook_start_with(const HookInstaller& installer,
                        const uint16_t* target_title, void (*signal)(void),
                        uint32_t* win32_error) {
  if (target_title == nullptr || target_title[0] == 0) {
    return BGC_INVALID_ARGUMENT;
  }
  // Window titles are read into BGC_TITLE_CHARS units, so a read that fills
  // the buffer may be a truncated longer title. A target that long could match
  // such a window by its prefix, so refuse it instead of truncating it.
  size_t length = 0;
  while (target_title[length] != 0) {
    if (++length >= BGC_TITLE_CHARS - 1) return BGC_INVALID_ARGUMENT;
  }
  if (win32_error != nullptr) *win32_error = 0;
  AcquireSRWLockExclusive(&g_api_lock);
  bool expected = false;
  if (!g_guard.compare_exchange_strong(expected, true)) {
    ReleaseSRWLockExclusive(&g_api_lock);
    return BGC_ALREADY_STARTED;
  }
  if (g_thread != nullptr) {  // handle of a thread that ended late
    CloseHandle(g_thread);
    g_thread = nullptr;
  }
  for (size_t n = 0; n <= length; n++) {
    g_target[n] = static_cast<wchar_t>(target_title[n]);
  }
  g_signal = signal;
  ring_clear(g_ring);

  ThreadStart start = {};
  start.installer = installer;
  start.ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (start.ready == nullptr) {
    if (win32_error != nullptr) *win32_error = GetLastError();
    g_guard.store(false);
    ReleaseSRWLockExclusive(&g_api_lock);
    return BGC_UNAVAILABLE;
  }
  HANDLE thread = CreateThread(nullptr, 0, hook_thread, &start, 0, nullptr);
  if (thread == nullptr) {
    if (win32_error != nullptr) *win32_error = GetLastError();
    CloseHandle(start.ready);
    g_guard.store(false);
    ReleaseSRWLockExclusive(&g_api_lock);
    return BGC_UNAVAILABLE;
  }
  WaitForSingleObject(start.ready, INFINITE);
  int32_t status = BGC_OK;
  if (start.ok) {
    g_thread = thread;
  } else {
    status = BGC_UNAVAILABLE;
    if (win32_error != nullptr) *win32_error = start.error;
    WaitForSingleObject(thread, INFINITE);  // no thread is left running
    CloseHandle(thread);
  }
  CloseHandle(start.ready);
  ReleaseSRWLockExclusive(&g_api_lock);
  return status;
}

}  // namespace bgc

BGC_API int32_t bgc_hook_start(const uint16_t* target_title,
                               void (*signal)(void), uint32_t* win32_error) {
  return bgc::hook_start_with(bgc::hook_real_installer(), target_title, signal,
                              win32_error);
}

BGC_API int32_t bgc_hook_stop(void) {
  using namespace bgc;
  AcquireSRWLockExclusive(&g_api_lock);
  if (g_thread == nullptr) {
    ReleaseSRWLockExclusive(&g_api_lock);
    return BGC_NOT_STARTED;
  }
  // Only post while the thread is still alive. g_thread stays open until the
  // join below succeeds, and Windows does not reuse a thread id while a handle
  // to that thread is open, so the id cannot name a recycled thread.
  if (WaitForSingleObject(g_thread, 0) == WAIT_TIMEOUT) {
    DWORD tid = g_thread_id.load();
    if (tid != 0) PostThreadMessageW(tid, WM_QUIT, 0, 0);
  }
  if (WaitForSingleObject(g_thread, 1000) != WAIT_OBJECT_0) {
    // Guard stays held; the thread releases it when it finally ends.
    ReleaseSRWLockExclusive(&g_api_lock);
    return BGC_STOP_TIMED_OUT;
  }
  CloseHandle(g_thread);
  g_thread = nullptr;
  ring_clear(g_ring);
  ReleaseSRWLockExclusive(&g_api_lock);
  return BGC_OK;
}

BGC_API uint32_t bgc_hook_drain(bgc_trigger_event* events, uint32_t capacity,
                                uint32_t* dropped) {
  return bgc::ring_drain(bgc::g_ring, events, capacity, dropped);
}
