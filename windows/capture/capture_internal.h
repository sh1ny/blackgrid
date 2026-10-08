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
// Same as bgc_hook_start with an injectable installer.
int32_t hook_start_with(const HookInstaller& installer,
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
