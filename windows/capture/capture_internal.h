// Internal seams for the capture DLL and its native self-test (design D9).
// Everything here is pure decision logic or an injectable Win32 boundary, so
// the self-test can exercise it without a real hook, a screen or a game.
#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <stdint.h>

#include <string>
#include <vector>

#include "capture.h"

namespace bgc {

// --- Hook filter (D2) --------------------------------------------------------

// Reads the title of hwnd into buf (cap code units). False when unavailable.
typedef bool (*TitleReaderFn)(void* ctx, HWND hwnd, wchar_t* buf, int cap);

// Pure decision: should this mouse event become a trigger? The title reader is
// never invoked when the foreground window belongs to our own process.
bool hook_filter_accepts(int nCode, WPARAM msg, HWND foreground,
                         uint32_t foreground_pid, uint32_t own_pid,
                         TitleReaderFn read_title, void* title_ctx,
                         const wchar_t* target_title);

// --- Trigger ring (D2) -------------------------------------------------------

struct Ring {
  SRWLOCK lock = SRWLOCK_INIT;
  bgc_trigger_event slots[BGC_RING_CAPACITY] = {};
  uint32_t head = 0;  // index of the oldest event
  uint32_t count = 0;
  uint32_t dropped = 0;
  bool signal_pending = false;
};

// Appends under the lock (dropping and counting the oldest when full), then
// test-and-sets signal_pending. Returns true only when this call set it, so
// the caller posts exactly one wake-up, after the lock is released.
bool ring_append(Ring& ring, const bgc_trigger_event& event);
// Copies the oldest events (at most capacity), empties the ring, clears
// signal_pending and reports the drops since the previous drain. Events that
// do not fit in capacity are discarded and counted as dropped.
uint32_t ring_drain(Ring& ring, bgc_trigger_event* events, uint32_t capacity,
                    uint32_t* dropped);
// Clears events, drop count and the pending flag.
void ring_clear(Ring& ring);
// Clears only the pending flag (a wake-up could not be posted).
void ring_cancel_signal(Ring& ring);
bool ring_signal_pending(Ring& ring);

// The target-window half of the filter, shared by both sources: a foreground
// window that is not ours and whose title equals the target.
bool target_window_accepts(HWND foreground, uint32_t foreground_pid,
                           uint32_t own_pid, TitleReaderFn read_title,
                           void* title_ctx, const wchar_t* target_title);

// --- Hook procedure core (D2) --------------------------------------------------

struct HookEnv {
  HWND (*foreground)();
  uint32_t (*window_pid)(HWND hwnd, uint32_t* tid);  // 0 when unknown
  TitleReaderFn read_title;
  void* title_ctx;
  LRESULT (*call_next)(int nCode, WPARAM wParam, LPARAM lParam);
  void (*post_signal)();  // wake the hook thread; failure handled by caller
  int64_t (*qpc)();
  uint32_t own_pid;
};

// The whole callback: filter, append, request a drain, and always pass the
// event on. lParam points at an MSLLHOOKSTRUCT for nCode >= 0.
LRESULT hook_proc_core(const HookEnv& env, Ring& ring,
                       const wchar_t* target_title, int nCode, WPARAM wParam,
                       LPARAM lParam);

// --- Hotkey (D1, D2, D5) -------------------------------------------------------

// Everything the WM_HOTKEY branch reads, injectable. It runs on the input
// thread, the thread that delivers signals, so `signal` is called directly.
struct HotkeyEnv {
  HWND (*foreground)();
  uint32_t (*window_pid)(HWND hwnd, uint32_t* tid);  // 0 when unknown
  TitleReaderFn read_title;
  void* title_ctx;
  bool (*cursor)(POINT* out);  // physical screen point; false when unreadable
  void (*signal)();
  int64_t (*qpc)();
  uint32_t own_pid;
};

// The whole WM_HOTKEY handling: foreground, own-process and title checks,
// cursor read, one append with source BGC_TRIGGER_HOTKEY, and the coalesced
// signal. True when an event was appended. Never waits.
bool hotkey_core(const HotkeyEnv& env, Ring& ring, const wchar_t* target_title);

// The OS registration boundary, called only on the input thread.
struct HotkeyRegistrar {
  bool (*register_key)(int id, uint32_t modifiers, uint32_t vk,
                       DWORD* win32_error);  // false on refusal
  void (*unregister_key)(int id);
};
const HotkeyRegistrar& hotkey_real_registrar();

// What the input thread holds: ids 1 and 2 (the swap uses the one that is not
// live). vk[id] is 0 when the id is not registered.
struct HotkeyState {
  uint32_t vk[3] = {0, 0, 0};
  int active = 0;  // id of the live registration, 0 for none
};

// One rebind request, shared by the caller of bgc_hotkey_set and the input
// thread. A single lock guards every field, so the caller's timeout marking and
// the thread's final abandoned check and completion cannot interleave.
struct HotkeySlot {
  SRWLOCK lock = SRWLOCK_INIT;
  HANDLE answered = nullptr;  // manual-reset: the thread completed the request
  bool reserved = false;      // from the request until the thread is done with it
  bool abandoned = false;     // the caller stopped waiting
  bool done = false;          // the thread answered a caller that still waits
  uint32_t vk = 0;
  int32_t status = BGC_OK;
  uint32_t win32_error = 0;
  HotkeySlot();
  ~HotkeySlot();
  HotkeySlot(const HotkeySlot&) = delete;
  HotkeySlot& operator=(const HotkeySlot&) = delete;
};

// 0 (off) or VK_F1..VK_F24.
bool hotkey_vk_valid(uint32_t vk);
// The caller side of bgc_hotkey_set. `installed` is whether the hook is held;
// `post` asks the input thread to run hotkey_service and returns false when it
// cannot. Waits at most timeout_ms.
typedef bool (*HotkeyPostFn)(void* ctx);
int32_t hotkey_request(HotkeySlot& slot, bool installed, HotkeyPostFn post,
                       void* post_ctx, uint32_t vk, uint32_t timeout_ms,
                       uint32_t* win32_error);
// The input thread's side: performs the pending request with the two-id swap.
void hotkey_service(HotkeySlot& slot, const HotkeyRegistrar& registrar,
                    HotkeyState& state);
// Forgets a request left over from a thread that ended (a new start).
void hotkey_slot_reset(HotkeySlot& slot);

// --- Hook lifecycle (D2) -------------------------------------------------------

struct HookInstaller {
  HHOOK (*install)(HOOKPROC proc, DWORD* win32_error);  // null on failure
  void (*uninstall)(HHOOK hook);
};
const HookInstaller& hook_real_installer();
// The module whose image contains address (null on failure). A global hook's
// hMod must name the module containing the hook procedure: in the shipped
// build that is blackgrid_capture.dll, not the executable.
HMODULE module_containing(const void* address);
// Input-thread exit: unregisters every hotkey id still held, completes a
// pending request with BGC_NOT_STARTED, and only then removes the hook.
void hotkey_teardown(HotkeySlot& slot, const HotkeyRegistrar& registrar,
                     HotkeyState& state, const HookInstaller& installer,
                     HHOOK hook);
// Same as bgc_hook_start with an injectable installer.
int32_t hook_start_with(const HookInstaller& installer,
                        const uint16_t* target_title, void (*signal)(void),
                        uint32_t* win32_error);
// ... and an injectable hotkey registrar.
int32_t hook_start_with(const HookInstaller& installer,
                        const HotkeyRegistrar& registrar,
                        const uint16_t* target_title, void (*signal)(void),
                        uint32_t* win32_error);
// True while an installation (or a thread that has not ended) is held.
bool hook_guard_held();

// --- All-zero check (D3) -------------------------------------------------------

// True when every B, G and R byte is 0; the fourth byte of each pixel is
// ignored.
bool bgr_all_zero(const uint8_t* pixels, int width, int height, int stride);

// --- Frame registry (D7) -------------------------------------------------------

struct FrameMemory {
  HBITMAP bitmap = nullptr;
  void* bits = nullptr;
};
typedef bool (*FrameAllocFn)(int width, int height, FrameMemory* out,
                             DWORD* win32_error);
typedef void (*FrameFreeFn)(FrameMemory* memory);

FrameAllocFn real_frame_alloc();
FrameFreeFn real_frame_free();

struct Registry {
  struct Slot {
    uint32_t generation = 0;
    bool live = false;   // reserved: counts against the budget
    bool ready = false;  // memory attached
    FrameMemory memory;
    int32_t width = 0;
    int32_t height = 0;
    int32_t stride = 0;
  };
  SRWLOCK lock = SRWLOCK_INIT;
  Slot slots[BGC_FRAME_SLOTS];
  FrameAllocFn alloc = nullptr;
  FrameFreeFn free_memory = nullptr;
};

void registry_init(Registry& reg, FrameAllocFn alloc, FrameFreeFn free_memory);
// Reserves a slot and returns its frame id, or 0 when all slots are live.
uint64_t registry_reserve(Registry& reg);
// Allocates the pixels for a reserved id (outside the lock).
bool registry_allocate(Registry& reg, uint64_t id, int width, int height,
                       DWORD* win32_error);
// Generation-checked; stale, repeated or unknown ids are no-ops.
void registry_release(Registry& reg, uint64_t id);
// True when id is live and has memory attached.
bool registry_info(Registry& reg, uint64_t id, bgc_frame_view* out,
                   HBITMAP* bitmap = nullptr);
uint32_t registry_live_count(Registry& reg);
Registry& global_registry();

// --- Process listing (D6) ------------------------------------------------------

struct ProcessEntry {
  uint32_t pid = 0;
  std::wstring exe;
};
// Toolhelp snapshot listing; never opens a process.
bool list_processes_real(std::vector<ProcessEntry>* out, DWORD* win32_error);
// BGC_OK, BGC_NOT_FOUND or BGC_CAPTURE_FAILED (name does not fit).
int32_t exe_name_lookup(const std::vector<ProcessEntry>& listing, uint32_t pid,
                        uint16_t* name, uint32_t capacity_chars);
// Case-insensitive match for EscapeFromTarkov.exe / EscapeFromTarkov_BE.exe.
bool listing_has_game(const std::vector<ProcessEntry>& listing,
                      std::wstring* which = nullptr);

}  // namespace bgc
