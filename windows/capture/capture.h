// Blackgrid input and capture boundary (ADR-0010): a versioned C ABI over a
// low-level mouse hook thread, window snapshots, desktop-GDI capture and a
// fixed native frame registry. Native code reports facts only; validation,
// planning, coherence and blank policy live in Dart (design D3). Nothing here
// opens a handle to, reads, writes or sends input to another process (D6).
#pragma once

#include <stdint.h>

#ifdef BLACKGRID_CAPTURE_EXPORTS
#define BGC_API extern "C" __declspec(dllexport)
#else
#define BGC_API extern "C" __declspec(dllimport)
#endif

// Bumped whenever a signature, struct layout, status code or semantic changes.
#define BGC_ABI_VERSION 1

// Status codes. 0 is success; every other value is a typed outcome.
#define BGC_OK 0
#define BGC_TARGET_GONE 1          // window destroyed or handle invalid
#define BGC_FRAME_BUDGET 2         // 4 frames live; nothing acquired
#define BGC_CAPTURE_FAILED 3       // GDI/Win32 failure; win32_error is set
#define BGC_INVALID_ARGUMENT 4     // null pointer, empty or oversized rect
#define BGC_ALREADY_STARTED 5      // hook installation already held
#define BGC_UNAVAILABLE 6          // hook install refused; win32_error is set
#define BGC_STOP_TIMED_OUT 7       // hook thread did not end within 1 s
#define BGC_NOT_STARTED 8          // stop without a held installation
#define BGC_FRAME_RELEASED 9       // stale, released or unknown frame id
#define BGC_NOT_FOUND 10           // no process with that id in the listing

// Bounds, checked natively as well as in Dart.
#define BGC_RING_CAPACITY 16
#define BGC_FRAME_SLOTS 4
#define BGC_MAX_SIDE 8192
#define BGC_MAX_PIXELS (24 * 1024 * 1024)
#define BGC_TITLE_CHARS 256        // UTF-16 code units incl. terminating NUL
#define BGC_EXE_CHARS 260          // UTF-16 code units incl. terminating NUL

// A rectangle in signed physical desktop pixels (PerMonitorV2).
typedef struct bgc_rect {
  int32_t left;
  int32_t top;
  int32_t width;
  int32_t height;
} bgc_rect;  // 16 bytes

// Window facts. exe name is not part of it: Dart resolves and caches it with
// bgc_process_name keyed by (hwnd, pid, tid) (D6).
typedef struct bgc_window_snapshot {
  uint64_t hwnd;
  uint32_t pid;
  uint32_t tid;
  uint32_t minimised;        // 0 or 1
  uint32_t foreground;       // 0 or 1 (GetForegroundWindow() == hwnd)
  uint32_t dpi;              // GetDpiForWindow
  uint32_t reserved;         // 0
  bgc_rect client;           // client area, desktop coordinates
  bgc_rect monitor;          // monitor rectangle, desktop coordinates
  bgc_rect virtual_desktop;  // SM_XVIRTUALSCREEN..SM_CYVIRTUALSCREEN
  uint16_t title[BGC_TITLE_CHARS];  // InternalGetWindowText, NUL-terminated
} bgc_window_snapshot;  // 592 bytes

// One mouse release accepted by the hook filter.
typedef struct bgc_trigger_event {
  int32_t x;        // physical screen point (MSLLHOOKSTRUCT.pt), signed
  int32_t y;
  uint64_t hwnd;    // foreground window at the release
  uint32_t pid;
  uint32_t tid;
  int64_t qpc;      // QueryPerformanceCounter at the callback
} bgc_trigger_event;  // 32 bytes

// Result of one bgc_capture call. pre and post are taken immediately before
// and after the BitBlt. all_zero covers the B, G and R bytes only.
typedef struct bgc_capture_result {
  uint64_t frame_id;     // 0 unless status is BGC_OK
  int64_t qpc_before;    // just before acquisition
  int64_t qpc_after;     // just after acquisition
  uint32_t all_zero;     // 0 or 1
  uint32_t win32_error;  // set for BGC_CAPTURE_FAILED
  bgc_window_snapshot pre;
  bgc_window_snapshot post;
} bgc_capture_result;  // 1216 bytes

// A live frame: 32 bpp BGRX, top-down, fourth byte undefined.
typedef struct bgc_frame_view {
  uint8_t* pixels;
  int32_t width;
  int32_t height;
  int32_t stride;   // bytes per row, >= width * 4
  int32_t reserved; // 0
} bgc_frame_view;  // 24 bytes

BGC_API uint32_t bgc_abi(void);

// --- Trigger hook (D2) ---
// Starts the one-per-process hook thread and waits until it reports whether
// WH_MOUSE_LL was installed. target_title is UTF-16, NUL-terminated and is
// copied. signal is invoked (with no payload) from the hook thread's loop when
// a drain is wanted; it must be a NativeCallable.listener. On BGC_UNAVAILABLE
// *win32_error is set and no thread is left running.
BGC_API int32_t bgc_hook_start(const uint16_t* target_title,
                               void (*signal)(void), uint32_t* win32_error);
// Unhooks on the hook thread and joins it for up to 1 s. On
// BGC_STOP_TIMED_OUT the installation guard stays held until the thread ends.
BGC_API int32_t bgc_hook_stop(void);
// Copies and empties the ring and clears the pending signal, in one critical
// section. Returns the number of events written (<= capacity); *dropped
// receives the number of events dropped since the previous drain.
BGC_API uint32_t bgc_hook_drain(bgc_trigger_event* events, uint32_t capacity,
                                uint32_t* dropped);

// --- Snapshot and capture (D3, D6) ---
// BGC_OK or BGC_TARGET_GONE (snapshot zeroed).
BGC_API int32_t bgc_snapshot(uint64_t hwnd, bgc_window_snapshot* out);
// Executable file name (no path) of pid from a toolhelp process listing.
// BGC_OK, BGC_NOT_FOUND or BGC_CAPTURE_FAILED. Never opens the process.
BGC_API int32_t bgc_process_name(uint32_t pid, uint16_t* name,
                                 uint32_t capacity_chars);
// Reserves a slot, snapshots (pre), BitBlts rect from the screen DC into a
// top-down 32 bpp DIB section, snapshots (post) and computes all_zero.
// BGC_OK, BGC_TARGET_GONE, BGC_FRAME_BUDGET, BGC_CAPTURE_FAILED or
// BGC_INVALID_ARGUMENT. On any non-OK status no slot stays reserved.
BGC_API int32_t bgc_capture(uint64_t hwnd, const bgc_rect* rect,
                            bgc_capture_result* out);

// --- Frame registry (D7) ---
// Frame id = (slot << 32) | generation; generation is never 0.
BGC_API int32_t bgc_frame_info(uint64_t frame_id, bgc_frame_view* out);
// Generation-checked; stale or repeated ids are no-ops.
BGC_API void bgc_frame_release(uint64_t frame_id);
BGC_API uint32_t bgc_frame_live_count(void);
// NativeFinalizer entry: token is the frame id cast to a pointer.
BGC_API void bgc_frame_finalize(void* token);

// --- Monotonic clock shared by triggers and captures ---
BGC_API int64_t bgc_qpc_now(void);
BGC_API int64_t bgc_qpc_frequency(void);
