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
  return target_window_accepts(foreground, foreground_pid, own_pid, read_title,
                               title_ctx, target_title);
}

bool target_window_accepts(HWND foreground, uint32_t foreground_pid,
                           uint32_t own_pid, TitleReaderFn read_title,
                           void* title_ctx, const wchar_t* target_title) {
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
      event.source = BGC_TRIGGER_MOUSE;
      // ring_append has left its critical section by the time it returns, so
      // the wake-up is requested outside the lock.
      if (ring_append(ring, event)) env.post_signal();
    }
  }
  return env.call_next(nCode, wParam, lParam);
}

// --- Hotkey core (D2) ----------------------------------------------------------------

bool hotkey_core(const HotkeyEnv& env, Ring& ring,
                 const wchar_t* target_title) {
  HWND foreground = env.foreground();
  uint32_t tid = 0;
  uint32_t pid = foreground != nullptr ? env.window_pid(foreground, &tid) : 0;
  if (!target_window_accepts(foreground, pid, env.own_pid, env.read_title,
                             env.title_ctx, target_title)) {
    return false;
  }
  POINT point = {};
  if (!env.cursor(&point)) return false;
  bgc_trigger_event event = {};
  event.x = point.x;
  event.y = point.y;
  event.hwnd = reinterpret_cast<uint64_t>(foreground);
  event.pid = pid;
  event.tid = tid;
  event.qpc = env.qpc();
  event.source = BGC_TRIGGER_HOTKEY;
  // This runs on the thread that delivers signals, so the wake-up is a direct
  // call instead of a posted message. The ring lock is already released.
  if (ring_append(ring, event) && env.signal != nullptr) env.signal();
  return true;
}

// --- Hotkey request slot and swap (D5) -------------------------------------------------

HotkeySlot::HotkeySlot() {
  answered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
}
HotkeySlot::~HotkeySlot() {
  if (answered != nullptr) CloseHandle(answered);
}

bool hotkey_vk_valid(uint32_t vk) {
  return vk == 0 || (vk >= 0x70 && vk <= 0x87);  // off, or VK_F1..VK_F24
}

int32_t hotkey_request(HotkeySlot& slot, bool installed, HotkeyPostFn post,
                       void* post_ctx, uint32_t vk, uint32_t timeout_ms,
                       uint32_t* win32_error) {
  if (win32_error != nullptr) *win32_error = 0;
  if (!hotkey_vk_valid(vk)) return BGC_INVALID_ARGUMENT;
  if (!installed) return BGC_NOT_STARTED;

  AcquireSRWLockExclusive(&slot.lock);
  if (slot.reserved) {  // an earlier request is still unanswered
    ReleaseSRWLockExclusive(&slot.lock);
    return BGC_HOTKEY_TIMED_OUT;
  }
  slot.reserved = true;
  slot.abandoned = false;
  slot.done = false;
  slot.vk = vk;
  slot.status = BGC_OK;
  slot.win32_error = 0;
  ResetEvent(slot.answered);
  ReleaseSRWLockExclusive(&slot.lock);

  if (!post(post_ctx)) {  // nothing was queued: the thread cannot answer
    AcquireSRWLockExclusive(&slot.lock);
    slot.reserved = false;
    ReleaseSRWLockExclusive(&slot.lock);
    return BGC_NOT_STARTED;
  }

  WaitForSingleObject(slot.answered, timeout_ms);
  // One lock decides between "answered" and "gave up", so a timeout never
  // reports hotkeyTimedOut for a swap the thread kept.
  AcquireSRWLockExclusive(&slot.lock);
  int32_t status;
  if (slot.done) {
    status = slot.status;
    if (win32_error != nullptr) *win32_error = slot.win32_error;
    slot.reserved = false;
  } else {
    slot.abandoned = true;
    status = BGC_HOTKEY_TIMED_OUT;
  }
  ReleaseSRWLockExclusive(&slot.lock);
  return status;
}

namespace {

// Completes the request; the caller holds slot.lock. An abandoned request has
// no caller any more, so it only frees the slot.
void complete_locked(HotkeySlot& slot, int32_t status, DWORD error) {
  if (slot.abandoned) {
    slot.reserved = false;
    return;
  }
  slot.status = status;
  slot.win32_error = error;
  slot.done = true;
  SetEvent(slot.answered);
}

void release_id(const HotkeyRegistrar& registrar, HotkeyState& state, int id) {
  if (id == 0 || state.vk[id] == 0) return;
  registrar.unregister_key(id);
  state.vk[id] = 0;
}

}  // namespace

void hotkey_service(HotkeySlot& slot, const HotkeyRegistrar& registrar,
                    HotkeyState& state) {
  AcquireSRWLockExclusive(&slot.lock);
  if (!slot.reserved || slot.done) {  // nothing pending
    ReleaseSRWLockExclusive(&slot.lock);
    return;
  }
  if (slot.abandoned) {  // the caller is gone: change nothing
    slot.reserved = false;
    ReleaseSRWLockExclusive(&slot.lock);
    return;
  }
  const uint32_t vk = slot.vk;
  ReleaseSRWLockExclusive(&slot.lock);

  const int old_id = state.active;
  const uint32_t old_vk = old_id != 0 ? state.vk[old_id] : 0;

  if (vk == old_vk) {  // the same key, or off while off: nothing to do
    AcquireSRWLockExclusive(&slot.lock);
    complete_locked(slot, BGC_OK, 0);
    ReleaseSRWLockExclusive(&slot.lock);
    return;
  }

  if (vk == 0) {  // off: release the live key unless the caller gave up
    AcquireSRWLockExclusive(&slot.lock);
    if (!slot.abandoned) {
      release_id(registrar, state, old_id);
      state.active = 0;
    }
    complete_locked(slot, BGC_OK, 0);
    ReleaseSRWLockExclusive(&slot.lock);
    return;
  }

  // Register the new key under the id the live key is not using.
  const int new_id = old_id == 1 ? 2 : 1;
  DWORD error = 0;
  if (!registrar.register_key(new_id, MOD_NOREPEAT, vk, &error)) {
    AcquireSRWLockExclusive(&slot.lock);
    complete_locked(slot, BGC_HOTKEY_UNAVAILABLE,
                    error != 0 ? error : ERROR_GEN_FAILURE);
    ReleaseSRWLockExclusive(&slot.lock);
    return;
  }
  state.vk[new_id] = vk;

  // The final abandoned check, the release of one key and the completion share
  // one critical section with the caller's timeout marking.
  AcquireSRWLockExclusive(&slot.lock);
  if (slot.abandoned) {
    release_id(registrar, state, new_id);  // only the new key; the old stays
  } else {
    release_id(registrar, state, old_id);
    state.active = new_id;
  }
  complete_locked(slot, BGC_OK, 0);
  ReleaseSRWLockExclusive(&slot.lock);
}

void hotkey_slot_reset(HotkeySlot& slot) {
  AcquireSRWLockExclusive(&slot.lock);
  slot.reserved = false;
  slot.abandoned = false;
  slot.done = false;
  ResetEvent(slot.answered);
  ReleaseSRWLockExclusive(&slot.lock);
}

void hotkey_teardown(HotkeySlot& slot, const HotkeyRegistrar& registrar,
                     HotkeyState& state, const HookInstaller& installer,
                     HHOOK hook) {
  for (int id = 1; id <= 2; id++) release_id(registrar, state, id);
  state.active = 0;
  AcquireSRWLockExclusive(&slot.lock);
  if (slot.reserved && !slot.done) complete_locked(slot, BGC_NOT_STARTED, 0);
  ReleaseSRWLockExclusive(&slot.lock);
  installer.uninstall(hook);  // the hotkeys are gone before the hook is
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
HotkeySlot g_hotkey_slot;
// The longest bgc_hotkey_set waits for the input thread (D5).
const uint32_t kHotkeyWaitMs = 1000;
const UINT kRebindMessage = WM_APP + 1;

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
// Called on the input thread itself, which is the thread that delivers signals.
void real_signal_direct() {
  void (*signal)(void) = g_signal;
  if (signal != nullptr) signal();
}
bool real_cursor(POINT* out) { return GetCursorPos(out) != FALSE; }

bool real_register_key(int id, uint32_t modifiers, uint32_t vk, DWORD* error) {
  // A null window: WM_HOTKEY lands in the calling (input) thread's queue.
  if (!RegisterHotKey(nullptr, id, modifiers, vk)) {
    *error = GetLastError();
    return false;
  }
  return true;
}
void real_unregister_key(int id) { UnregisterHotKey(nullptr, id); }

bool real_post_rebind(void*) {
  DWORD tid = g_thread_id.load();
  return tid != 0 && PostThreadMessageW(tid, kRebindMessage, 0, 0);
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
  HotkeyRegistrar registrar;
  HANDLE ready;
  bool ok;
  DWORD error;
};

DWORD WINAPI hook_thread(LPVOID param) {
  ThreadStart* start = static_cast<ThreadStart*>(param);
  const HookInstaller installer = start->installer;
  const HotkeyRegistrar registrar = start->registrar;
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

  HotkeyState hotkeys;  // touched by this thread only
  HotkeyEnv hotkey_env = {};
  hotkey_env.foreground = real_foreground;
  hotkey_env.window_pid = real_window_pid;
  hotkey_env.read_title = real_read_title;
  hotkey_env.cursor = real_cursor;
  hotkey_env.signal = real_signal_direct;
  hotkey_env.qpc = real_qpc;
  hotkey_env.own_pid = GetCurrentProcessId();

  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (msg.message == WM_APP) {
      real_signal_direct();
    } else if (msg.message == kRebindMessage) {
      hotkey_service(g_hotkey_slot, registrar, hotkeys);
    } else if (msg.message == WM_HOTKEY) {
      // Only the live id: a press queued before a release is ignored.
      if (hotkeys.active != 0 && msg.wParam == static_cast<WPARAM>(hotkeys.active)) {
        hotkey_core(hotkey_env, g_ring, g_target);
      }
    }
  }
  // Hotkeys first, then the hook; a pending rebind completes NOT_STARTED.
  hotkey_teardown(g_hotkey_slot, registrar, hotkeys, installer, hook);
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

const HotkeyRegistrar& hotkey_real_registrar() {
  static const HotkeyRegistrar registrar = {real_register_key,
                                            real_unregister_key};
  return registrar;
}

bool hook_guard_held() { return g_guard.load(); }

int32_t hook_start_with(const HookInstaller& installer,
                        const uint16_t* target_title, void (*signal)(void),
                        uint32_t* win32_error) {
  return hook_start_with(installer, hotkey_real_registrar(), target_title,
                         signal, win32_error);
}

int32_t hook_start_with(const HookInstaller& installer,
                        const HotkeyRegistrar& registrar,
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
  hotkey_slot_reset(g_hotkey_slot);  // no thread holds a request any more

  ThreadStart start = {};
  start.installer = installer;
  start.registrar = registrar;
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

BGC_API int32_t bgc_hotkey_set(uint32_t vk, uint32_t* win32_error) {
  using namespace bgc;
  AcquireSRWLockExclusive(&g_api_lock);
  // A held installation whose thread is still running.
  bool installed =
      g_thread != nullptr && WaitForSingleObject(g_thread, 0) == WAIT_TIMEOUT;
  int32_t status =
      hotkey_request(g_hotkey_slot, installed, real_post_rebind, nullptr, vk,
                     kHotkeyWaitMs, win32_error);
  ReleaseSRWLockExclusive(&g_api_lock);
  return status;
}
