// Native self-test for the capture boundary (design D9). It captures only the
// window it creates itself, never generates input, and refuses to run while a
// game process is listed. Every case prints PASS / FAIL / SKIP; the exit code
// is 0 only when nothing FAILed, 2 when the game guard refused.
#include "capture_internal.h"

#include <stdio.h>
#include <string.h>
#include <wchar.h>

#include <string>
#include <vector>

namespace {

using namespace bgc;

// --- Harness -----------------------------------------------------------------

enum class Kind { Pass, Fail, Skip };
struct Outcome {
  Kind kind;
  std::string reason;
};
Outcome pass() { return {Kind::Pass, ""}; }
Outcome fail(const std::string& reason) { return {Kind::Fail, reason}; }
Outcome skip(const std::string& reason) { return {Kind::Skip, reason}; }

std::string at(int line) { return " (selftest.cpp:" + std::to_string(line) + ")"; }

#define CHECK(cond)                                           \
  do {                                                        \
    if (!(cond)) return fail(std::string(#cond) + at(__LINE__)); \
  } while (0)

#define CHECK_EQ(actual, expected)                                          \
  do {                                                                      \
    long long a_ = (long long)(actual);                                     \
    long long e_ = (long long)(expected);                                   \
    if (a_ != e_)                                                           \
      return fail(std::string(#actual " = " + std::to_string(a_) +         \
                              ", expected " + std::to_string(e_)) +         \
                  at(__LINE__));                                            \
  } while (0)

struct Case {
  const char* name;
  Outcome (*run)();
};

// --- Fakes for the hook seams ---------------------------------------------------

struct TitleFake {
  const wchar_t* title;
  int calls;
};
bool fake_read_title(void* ctx, HWND, wchar_t* buf, int cap) {
  TitleFake* fake = static_cast<TitleFake*>(ctx);
  fake->calls++;
  wcsncpy_s(buf, static_cast<size_t>(cap), fake->title, _TRUNCATE);
  return fake->title[0] != 0;
}

const wchar_t kTarget[] = L"EscapeFromTarkov";
const HWND kFakeWindow = reinterpret_cast<HWND>(static_cast<uintptr_t>(0x1234));

HWND g_fake_foreground = nullptr;
uint32_t g_fake_pid = 500;
int g_next_calls = 0;
int g_post_calls = 0;
int64_t g_fake_qpc = 424242;

HWND fake_foreground() { return g_fake_foreground; }
uint32_t fake_window_pid(HWND, uint32_t* tid) {
  *tid = 77;
  return g_fake_pid;
}
LRESULT fake_call_next(int, WPARAM, LPARAM) {
  g_next_calls++;
  return 777;
}
void fake_post_signal() { g_post_calls++; }
int64_t fake_qpc() { return g_fake_qpc; }

HookEnv make_env(TitleFake* title) {
  HookEnv env = {};
  env.foreground = fake_foreground;
  env.window_pid = fake_window_pid;
  env.read_title = fake_read_title;
  env.title_ctx = title;
  env.call_next = fake_call_next;
  env.post_signal = fake_post_signal;
  env.qpc = fake_qpc;
  env.own_pid = 100;
  return env;
}

void reset_fakes() {
  g_fake_foreground = kFakeWindow;
  g_fake_pid = 500;
  g_next_calls = 0;
  g_post_calls = 0;
  g_fake_qpc = 424242;
}

bgc_trigger_event make_event(int32_t n) {
  bgc_trigger_event e = {};
  e.x = n;
  e.y = -n;
  e.hwnd = 0x1234;
  e.pid = 500;
  e.tid = 77;
  e.qpc = 1000 + n;
  return e;
}

// --- Hook filter cases -----------------------------------------------------------

Outcome filter_accepts_target_release_with_signed_point() {
  TitleFake title = {kTarget, 0};
  CHECK(hook_filter_accepts(0, WM_LBUTTONUP, kFakeWindow, 500, 100,
                            fake_read_title, &title, kTarget));
  CHECK_EQ(title.calls, 1);

  reset_fakes();
  Ring ring;
  HookEnv env = make_env(&title);
  MSLLHOOKSTRUCT info = {};
  info.pt.x = -1200;
  info.pt.y = 340;
  LRESULT r = hook_proc_core(env, ring, kTarget, 0, WM_LBUTTONUP,
                             reinterpret_cast<LPARAM>(&info));
  CHECK_EQ(r, 777);
  CHECK_EQ(g_post_calls, 1);
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 99;
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 1);
  CHECK_EQ(dropped, 0);
  CHECK_EQ(out[0].x, -1200);
  CHECK_EQ(out[0].y, 340);
  CHECK_EQ(out[0].hwnd, 0x1234);
  CHECK_EQ(out[0].pid, 500);
  CHECK_EQ(out[0].tid, 77);
  CHECK_EQ(out[0].qpc, 424242);
  return pass();
}

Outcome filter_rejects_other_title() {
  TitleFake title = {L"Notepad", 0};
  CHECK(!hook_filter_accepts(0, WM_LBUTTONUP, kFakeWindow, 500, 100,
                             fake_read_title, &title, kTarget));
  CHECK_EQ(title.calls, 1);
  TitleFake blank = {L"", 0};
  CHECK(!hook_filter_accepts(0, WM_LBUTTONUP, kFakeWindow, 500, 100,
                             fake_read_title, &blank, kTarget));
  return pass();
}

Outcome filter_rejects_non_left_release_messages() {
  TitleFake title = {kTarget, 0};
  const WPARAM rejected[] = {WM_LBUTTONDOWN, WM_RBUTTONUP, WM_RBUTTONDOWN,
                             WM_MOUSEWHEEL, WM_MOUSEMOVE, WM_MBUTTONUP};
  for (WPARAM msg : rejected) {
    CHECK(!hook_filter_accepts(0, msg, kFakeWindow, 500, 100, fake_read_title,
                               &title, kTarget));
  }
  CHECK(!hook_filter_accepts(-1, WM_LBUTTONUP, kFakeWindow, 500, 100,
                             fake_read_title, &title, kTarget));
  CHECK(!hook_filter_accepts(HC_NOREMOVE - 100, WM_LBUTTONUP, kFakeWindow, 500,
                             100, fake_read_title, &title, kTarget));
  return pass();
}

Outcome filter_rejects_null_foreground() {
  TitleFake title = {kTarget, 0};
  CHECK(!hook_filter_accepts(0, WM_LBUTTONUP, nullptr, 0, 100, fake_read_title,
                             &title, kTarget));
  CHECK_EQ(title.calls, 0);
  return pass();
}

Outcome filter_skips_own_process_without_title_read() {
  TitleFake title = {kTarget, 0};
  CHECK(!hook_filter_accepts(0, WM_LBUTTONUP, kFakeWindow, 100, 100,
                             fake_read_title, &title, kTarget));
  CHECK_EQ(title.calls, 0);

  reset_fakes();
  g_fake_pid = 100;  // the foreground window is ours
  Ring ring;
  HookEnv env = make_env(&title);
  MSLLHOOKSTRUCT info = {};
  hook_proc_core(env, ring, kTarget, 0, WM_LBUTTONUP,
                 reinterpret_cast<LPARAM>(&info));
  CHECK_EQ(title.calls, 0);
  CHECK_EQ(g_post_calls, 0);
  CHECK_EQ(g_next_calls, 1);
  bgc_trigger_event out[BGC_RING_CAPACITY];
  uint32_t dropped = 0;
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 0);
  return pass();
}

Outcome hook_proc_always_calls_next_hook() {
  TitleFake title = {kTarget, 0};
  Ring ring;
  HookEnv env = make_env(&title);
  MSLLHOOKSTRUCT info = {};
  LPARAM lp = reinterpret_cast<LPARAM>(&info);
  struct Probe {
    int nCode;
    WPARAM msg;
    HWND fg;
    uint32_t pid;
  };
  const Probe probes[] = {
      {0, WM_LBUTTONUP, kFakeWindow, 500},  // accepted
      {0, WM_LBUTTONUP, kFakeWindow, 100},  // own process
      {0, WM_LBUTTONUP, nullptr, 0},        // no foreground
      {0, WM_LBUTTONDOWN, kFakeWindow, 500},
      {0, WM_MOUSEWHEEL, kFakeWindow, 500},
      {-1, WM_LBUTTONUP, kFakeWindow, 500},
  };
  int expected = 0;
  for (const Probe& p : probes) {
    reset_fakes();
    g_fake_foreground = p.fg;
    g_fake_pid = p.pid;
    LRESULT r = hook_proc_core(env, ring, kTarget, p.nCode, p.msg, lp);
    CHECK_EQ(r, 777);
    CHECK_EQ(g_next_calls, 1);
    expected++;
  }
  CHECK_EQ(expected, 6);
  return pass();
}

// --- Ring cases ------------------------------------------------------------------

Outcome append_returns_without_drain_and_keeps_order() {
  Ring ring;
  for (int32_t i = 0; i < 5; i++) ring_append(ring, make_event(i));
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 99;
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 5);
  CHECK_EQ(dropped, 0);
  for (int32_t i = 0; i < 5; i++) {
    CHECK_EQ(out[i].x, i);
    CHECK_EQ(out[i].qpc, 1000 + i);
  }
  return pass();
}

Outcome ring_drops_oldest_and_reports_count() {
  Ring ring;
  for (int32_t i = 0; i < 20; i++) ring_append(ring, make_event(i));
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 16);
  CHECK_EQ(dropped, 4);
  for (int32_t i = 0; i < 16; i++) CHECK_EQ(out[i].x, i + 4);
  // The drop count is reported once.
  ring_append(ring, make_event(50));
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 1);
  CHECK_EQ(dropped, 0);
  return pass();
}

Outcome signal_coalesces_until_drain() {
  Ring ring;
  int requested = 0;
  for (int32_t i = 0; i < 3; i++) {
    if (ring_append(ring, make_event(i))) requested++;
  }
  CHECK_EQ(requested, 1);
  CHECK(ring_signal_pending(ring));
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 3);
  CHECK(!ring_signal_pending(ring));
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 0);
  CHECK(!ring_signal_pending(ring));
  return pass();
}

Outcome append_after_drain_resignals() {
  Ring ring;
  CHECK(ring_append(ring, make_event(1)));
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 1);
  CHECK(ring_append(ring, make_event(2)));
  CHECK(!ring_append(ring, make_event(3)));
  CHECK_EQ(ring_drain(ring, out, BGC_RING_CAPACITY, &dropped), 2);
  CHECK_EQ(out[0].x, 2);
  CHECK_EQ(out[1].x, 3);
  return pass();
}

// --- Hook lifecycle --------------------------------------------------------------

HHOOK failing_install(HOOKPROC, DWORD* error) {
  *error = ERROR_ACCESS_DENIED;
  return nullptr;
}
HHOOK fake_install(HOOKPROC, DWORD*) {
  return reinterpret_cast<HHOOK>(static_cast<uintptr_t>(1));
}
void fake_uninstall(HHOOK) {}
void ignore_signal() {}

Outcome install_failure_reports_error_and_ends_thread() {
  const uint16_t title[] = {'T', 0};
  HookInstaller failing = {failing_install, fake_uninstall};
  uint32_t error = 0;
  CHECK_EQ(hook_start_with(failing, title, ignore_signal, &error),
           BGC_UNAVAILABLE);
  CHECK_EQ(error, ERROR_ACCESS_DENIED);
  CHECK(!hook_guard_held());  // thread ended, nothing left running

  // A later start is not blocked by the failed one, and stop ends its thread.
  HookInstaller working = {fake_install, fake_uninstall};
  CHECK_EQ(hook_start_with(working, title, ignore_signal, &error), BGC_OK);
  CHECK(hook_guard_held());
  CHECK_EQ(hook_start_with(working, title, ignore_signal, &error),
           BGC_ALREADY_STARTED);
  CHECK_EQ(bgc_hook_stop(), BGC_OK);
  CHECK(!hook_guard_held());
  CHECK_EQ(bgc_hook_stop(), BGC_NOT_STARTED);
  return pass();
}

// --- All-zero --------------------------------------------------------------------

Outcome all_zero_ignores_fourth_byte() {
  const int w = 3, h = 2, stride = 16;  // 4 padding bytes per row
  uint8_t px[stride * h];
  memset(px, 0, sizeof(px));
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) px[y * stride + x * 4 + 3] = 0xFF;
    for (int p = w * 4; p < stride; p++) px[y * stride + p] = 0xAB;  // padding
  }
  CHECK(bgr_all_zero(px, w, h, stride));
  return pass();
}

Outcome all_zero_false_for_one_colour_byte() {
  const int w = 5, h = 3, stride = 20;
  for (int channel = 0; channel < 3; channel++) {
    uint8_t px[stride * h];
    memset(px, 0, sizeof(px));
    px[2 * stride + 4 * 4 + channel] = 1;  // last pixel of the last row
    CHECK(!bgr_all_zero(px, w, h, stride));
  }
  uint8_t first[stride * h];
  memset(first, 0, sizeof(first));
  first[0] = 1;
  CHECK(!bgr_all_zero(first, w, h, stride));
  return pass();
}

// --- Registry --------------------------------------------------------------------

uint8_t g_fake_pixels[BGC_FRAME_SLOTS + 2][64];
int g_fake_next = 0;
int g_fake_freed = 0;
bool fake_alloc(int, int, FrameMemory* out, DWORD*) {
  out->bitmap = nullptr;
  out->bits = g_fake_pixels[g_fake_next++ % (BGC_FRAME_SLOTS + 2)];
  return true;
}
void fake_free(FrameMemory*) { g_fake_freed++; }

Outcome registry_refuses_fifth_frame() {
  Registry reg;
  registry_init(reg, fake_alloc, fake_free);
  uint64_t ids[BGC_FRAME_SLOTS] = {};
  for (int i = 0; i < BGC_FRAME_SLOTS; i++) {
    ids[i] = registry_reserve(reg);
    CHECK(ids[i] != 0);
    CHECK((ids[i] & 0xFFFFFFFFu) != 0);  // generation is never 0
    DWORD err = 0;
    CHECK(registry_allocate(reg, ids[i], 4, 4, &err));
    for (int j = 0; j < i; j++) CHECK(ids[i] != ids[j]);
  }
  CHECK_EQ(registry_live_count(reg), 4);
  CHECK_EQ(registry_reserve(reg), 0);  // fifth is refused, nothing acquired
  CHECK_EQ(registry_live_count(reg), 4);

  bgc_frame_view view = {};
  CHECK(registry_info(reg, ids[0], &view));
  CHECK_EQ(view.width, 4);
  CHECK_EQ(view.height, 4);
  CHECK_EQ(view.stride, 16);
  CHECK(view.pixels != nullptr);

  registry_release(reg, ids[0]);
  CHECK_EQ(registry_live_count(reg), 3);
  registry_release(reg, ids[0]);  // repeated release is a no-op
  CHECK_EQ(registry_live_count(reg), 3);
  CHECK(!registry_info(reg, ids[0], &view));

  uint64_t again = registry_reserve(reg);
  CHECK(again != 0);
  CHECK(again != ids[0]);  // same slot, new generation
  registry_release(reg, ids[0]);  // stale id must not free the new frame
  CHECK_EQ(registry_live_count(reg), 4);
  registry_release(reg, 0);
  registry_release(reg, 0xFFFFFFFF00000001ull);  // unknown slot
  CHECK_EQ(registry_live_count(reg), 4);
  return pass();
}

// --- Process name ----------------------------------------------------------------

Outcome exe_name_from_toolhelp_for_own_pid() {
  uint16_t name[BGC_EXE_CHARS] = {};
  CHECK_EQ(bgc_process_name(GetCurrentProcessId(), name, BGC_EXE_CHARS), BGC_OK);
  wchar_t path[MAX_PATH] = {};
  CHECK(GetModuleFileNameW(nullptr, path, MAX_PATH) > 0);
  const wchar_t* base = wcsrchr(path, L'\\');
  base = base ? base + 1 : path;
  CHECK(_wcsicmp(reinterpret_cast<const wchar_t*>(name), base) == 0);

  // Injectable listing: unknown pid and a too-small buffer.
  std::vector<ProcessEntry> listing = {{4, L"System"}, {8, L"long_name.exe"}};
  CHECK_EQ(exe_name_lookup(listing, 4, name, BGC_EXE_CHARS), BGC_OK);
  CHECK_EQ(exe_name_lookup(listing, 5, name, BGC_EXE_CHARS), BGC_NOT_FOUND);
  CHECK_EQ(exe_name_lookup(listing, 8, name, 4), BGC_CAPTURE_FAILED);
  return pass();
}

// --- Game guard ------------------------------------------------------------------

Outcome guard_refuses_when_listing_contains_game() {
  std::vector<ProcessEntry> clean = {{4, L"System"}, {9, L"notepad.exe"}};
  CHECK(!listing_has_game(clean));
  std::vector<ProcessEntry> game = {{4, L"System"},
                                    {9, L"escapefromtarkov.EXE"}};
  std::wstring which;
  CHECK(listing_has_game(game, &which));
  CHECK(_wcsicmp(which.c_str(), L"EscapeFromTarkov.exe") == 0);
  std::vector<ProcessEntry> anticheat = {{7, L"EscapeFromTarkov_BE.exe"}};
  CHECK(listing_has_game(anticheat));
  return pass();
}

// --- Own window --------------------------------------------------------------------

const wchar_t kWindowClass[] = L"BlackgridCaptureSelftestWindow";
const wchar_t kWindowTitle[] = L"BlackgridCaptureSelftest";

// Known pattern: red ramps with x, green with y, blue is the xor.
void pattern_pixel(int x, int y, int w, int h, uint8_t* bgr) {
  bgr[0] = static_cast<uint8_t>((x ^ y) & 0xFF);
  bgr[1] = static_cast<uint8_t>(h > 1 ? (y * 255) / (h - 1) : 0);
  bgr[2] = static_cast<uint8_t>(w > 1 ? (x * 255) / (w - 1) : 0);
  if (bgr[0] == 0 && bgr[1] == 0 && bgr[2] == 0) bgr[0] = 1;  // never blank
}

LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      RECT rc;
      GetClientRect(hwnd, &rc);
      int w = rc.right, h = rc.bottom;
      if (w > 0 && h > 0) {
        std::vector<uint8_t> px(static_cast<size_t>(w) * h * 4, 0);
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            uint8_t* p = &px[(static_cast<size_t>(y) * w + x) * 4];
            pattern_pixel(x, y, w, h, p);
          }
        }
        BITMAPINFO bi = {};
        bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
        bi.bmiHeader.biWidth = w;
        bi.bmiHeader.biHeight = -h;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        SetDIBitsToDevice(dc, 0, 0, w, h, 0, 0, 0, h, px.data(), &bi,
                          DIB_RGB_COLORS);
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
    default:
      return DefWindowProcW(hwnd, msg, wp, lp);
  }
}

void pump(DWORD ms) {
  DWORD end = GetTickCount() + ms;
  MSG msg;
  while (GetTickCount() < end) {
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
    Sleep(10);
  }
}

bool register_window_class() {
  static bool done = false;
  if (done) return true;
  WNDCLASSW wc = {};
  wc.lpfnWndProc = window_proc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.lpszClassName = kWindowClass;
  if (!RegisterClassW(&wc)) return false;
  done = true;
  return true;
}

HWND create_window(bool visible) {
  if (!register_window_class()) return nullptr;
  HWND hwnd = CreateWindowExW(0, kWindowClass, kWindowTitle,
                              WS_POPUP, 120, 120, 420, 300, nullptr,
                              nullptr, GetModuleHandleW(nullptr), nullptr);
  if (hwnd && visible) {
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    UpdateWindow(hwnd);
  }
  return hwnd;
}

// The capture checks run only when the snapshot says the self-test's own
// window is the visible foreground window.
bool may_capture(int32_t status, const bgc_window_snapshot& s, HWND own) {
  return status == BGC_OK && s.hwnd == reinterpret_cast<uint64_t>(own) &&
         s.foreground == 1 && s.minimised == 0;
}

Outcome capture_checks_skip_when_not_foreground() {
  // A window that is never shown can never be foreground.
  HWND hidden = create_window(false);
  CHECK(hidden != nullptr);
  bgc_window_snapshot snap;
  memset(&snap, 0xCC, sizeof(snap));
  int32_t status = bgc_snapshot(reinterpret_cast<uint64_t>(hidden), &snap);
  CHECK_EQ(status, BGC_OK);
  CHECK_EQ(snap.foreground, 0);
  CHECK(!may_capture(status, snap, hidden));
  // Foreground, visible and matching is the only combination that proceeds.
  bgc_window_snapshot fg = snap;
  fg.foreground = 1;
  CHECK(may_capture(BGC_OK, fg, hidden));
  fg.minimised = 1;
  CHECK(!may_capture(BGC_OK, fg, hidden));
  DestroyWindow(hidden);
  return pass();
}

bool rect_inside(const bgc_rect& inner, const bgc_rect& outer) {
  return inner.left >= outer.left && inner.top >= outer.top &&
         static_cast<int64_t>(inner.left) + inner.width <=
             static_cast<int64_t>(outer.left) + outer.width &&
         static_cast<int64_t>(inner.top) + inner.height <=
             static_cast<int64_t>(outer.top) + outer.height;
}

bool same_rect(const bgc_rect& a, const bgc_rect& b) {
  return a.left == b.left && a.top == b.top && a.width == b.width &&
         a.height == b.height;
}

// Compares a captured frame with the pattern; (ox, oy) is the region origin
// relative to the client area. Returns the number of mismatched pixels.
int count_pattern_mismatches(uint64_t frame_id, int ox, int oy, int cw, int ch,
                             int* out_w, int* out_h) {
  bgc_frame_view view = {};
  if (bgc_frame_info(frame_id, &view) != BGC_OK) return -1;
  *out_w = view.width;
  *out_h = view.height;
  int bad = 0;
  for (int y = 0; y < view.height; y++) {
    for (int x = 0; x < view.width; x++) {
      uint8_t expect[3];
      pattern_pixel(ox + x, oy + y, cw, ch, expect);
      const uint8_t* p = view.pixels + static_cast<size_t>(y) * view.stride +
                         static_cast<size_t>(x) * 4;
      if (p[0] != expect[0] || p[1] != expect[1] || p[2] != expect[2]) bad++;
    }
  }
  return bad;
}

Outcome captures_own_window_pattern_and_geometry() {
  CHECK_EQ(bgc_abi(), BGC_ABI_VERSION);
  CHECK(bgc_qpc_frequency() > 0);
  CHECK_EQ(bgc_frame_live_count(), 0);

  HWND hwnd = create_window(true);
  CHECK(hwnd != nullptr);
  SetForegroundWindow(hwnd);
  pump(400);
  if (GetForegroundWindow() != hwnd) {
    DestroyWindow(hwnd);
    return skip("own window could not become foreground; nothing captured");
  }

  const uint64_t handle = reinterpret_cast<uint64_t>(hwnd);
  bgc_window_snapshot snap = {};
  int32_t status = bgc_snapshot(handle, &snap);
  if (!may_capture(status, snap, hwnd)) {
    DestroyWindow(hwnd);
    return skip("snapshot says own window is not the visible foreground window");
  }

  // Geometry against the Win32 view of the same window.
  RECT cr;
  GetClientRect(hwnd, &cr);
  POINT origin = {0, 0};
  ClientToScreen(hwnd, &origin);
  DWORD pid = 0;
  DWORD tid = GetWindowThreadProcessId(hwnd, &pid);
  CHECK_EQ(snap.pid, pid);
  CHECK_EQ(snap.tid, tid);
  CHECK_EQ(snap.client.left, origin.x);
  CHECK_EQ(snap.client.top, origin.y);
  CHECK_EQ(snap.client.width, cr.right);
  CHECK_EQ(snap.client.height, cr.bottom);
  CHECK_EQ(snap.dpi, GetDpiForWindow(hwnd));
  CHECK(snap.dpi >= 96);
  CHECK(snap.monitor.width > 0 && snap.monitor.height > 0);
  CHECK(rect_inside(snap.client, snap.virtual_desktop));
  CHECK(snap.virtual_desktop.width >= snap.monitor.width);
  CHECK(_wcsicmp(reinterpret_cast<const wchar_t*>(snap.title), kWindowTitle) == 0);
  const int cw = snap.client.width, ch = snap.client.height;
  CHECK(cw > 80 && ch > 60);

  // Targeted region.
  const bgc_rect region = {snap.client.left + 40, snap.client.top + 30, 64, 40};
  int64_t t0 = bgc_qpc_now();
  bgc_capture_result targeted = {};
  CHECK_EQ(bgc_capture(handle, &region, &targeted), BGC_OK);
  int64_t t1 = bgc_qpc_now();
  CHECK(targeted.frame_id != 0);
  CHECK_EQ(bgc_frame_live_count(), 1);
  CHECK_EQ(targeted.all_zero, 0);
  CHECK(targeted.qpc_before >= t0 && targeted.qpc_before <= targeted.qpc_after &&
        targeted.qpc_after <= t1);
  CHECK(targeted.pre.foreground == 1 && targeted.post.foreground == 1);
  CHECK(same_rect(targeted.pre.client, snap.client));
  CHECK(same_rect(targeted.post.client, snap.client));
  CHECK_EQ(targeted.pre.dpi, snap.dpi);
  CHECK_EQ(targeted.post.dpi, snap.dpi);
  CHECK(targeted.pre.hwnd == handle && targeted.post.hwnd == handle);
  CHECK(targeted.pre.pid == pid && targeted.post.pid == pid);
  int fw = 0, fh = 0;
  int bad = count_pattern_mismatches(targeted.frame_id, 40, 30, cw, ch, &fw, &fh);
  CHECK_EQ(fw, 64);
  CHECK_EQ(fh, 40);
  CHECK_EQ(bad, 0);

  // Full client.
  bgc_capture_result full = {};
  CHECK_EQ(bgc_capture(handle, &snap.client, &full), BGC_OK);
  CHECK_EQ(bgc_frame_live_count(), 2);
  CHECK_EQ(full.all_zero, 0);
  bad = count_pattern_mismatches(full.frame_id, 0, 0, cw, ch, &fw, &fh);
  CHECK_EQ(fw, cw);
  CHECK_EQ(fh, ch);
  CHECK_EQ(bad, 0);

  // Release: finalizer path and generation checks.
  bgc_frame_release(targeted.frame_id);
  bgc_frame_release(targeted.frame_id);  // repeated, no-op
  CHECK_EQ(bgc_frame_live_count(), 1);
  bgc_frame_view view = {};
  CHECK_EQ(bgc_frame_info(targeted.frame_id, &view), BGC_FRAME_RELEASED);
  bgc_frame_finalize(reinterpret_cast<void*>(static_cast<uintptr_t>(full.frame_id)));
  CHECK_EQ(bgc_frame_live_count(), 0);

  // Minimised: the snapshot reports it, and the capture decision refuses.
  ShowWindow(hwnd, SW_MINIMIZE);
  pump(400);
  bgc_window_snapshot mini = {};
  CHECK_EQ(bgc_snapshot(handle, &mini), BGC_OK);
  CHECK_EQ(mini.minimised, 1);
  CHECK(!may_capture(BGC_OK, mini, hwnd));

  // Destroyed: target gone, snapshot zeroed, no slot left behind.
  DestroyWindow(hwnd);
  bgc_window_snapshot gone;
  memset(&gone, 0xCC, sizeof(gone));
  CHECK_EQ(bgc_snapshot(handle, &gone), BGC_TARGET_GONE);
  bgc_window_snapshot zero = {};
  CHECK(memcmp(&gone, &zero, sizeof(zero)) == 0);
  bgc_capture_result after = {};
  CHECK_EQ(bgc_capture(handle, &region, &after), BGC_TARGET_GONE);
  CHECK_EQ(after.frame_id, 0);
  CHECK_EQ(bgc_frame_live_count(), 0);
  return pass();
}

// --- Extra cases beyond the named list ----------------------------------------------

Outcome abi_argument_validation() {
  CHECK_EQ(bgc_abi(), BGC_ABI_VERSION);
  CHECK_EQ(sizeof(bgc_rect), 16);
  CHECK_EQ(sizeof(bgc_window_snapshot), 592);
  CHECK_EQ(sizeof(bgc_trigger_event), 32);
  CHECK_EQ(sizeof(bgc_capture_result), 1216);
  CHECK_EQ(sizeof(bgc_frame_view), 24);
  bgc_capture_result res = {};
  const uint64_t any = 0x1000;  // not a window
  const bgc_rect ok = {0, 0, 10, 10};
  CHECK_EQ(bgc_capture(any, nullptr, &res), BGC_INVALID_ARGUMENT);
  CHECK_EQ(bgc_capture(any, &ok, nullptr), BGC_INVALID_ARGUMENT);
  const bgc_rect empty = {0, 0, 0, 10};
  CHECK_EQ(bgc_capture(any, &empty, &res), BGC_INVALID_ARGUMENT);
  const bgc_rect wide = {0, 0, BGC_MAX_SIDE + 1, 10};
  CHECK_EQ(bgc_capture(any, &wide, &res), BGC_INVALID_ARGUMENT);
  const bgc_rect huge = {0, 0, BGC_MAX_SIDE, BGC_MAX_SIDE};  // 64 Mpx
  CHECK_EQ(bgc_capture(any, &huge, &res), BGC_INVALID_ARGUMENT);
  CHECK_EQ(bgc_capture(any, &ok, &res), BGC_TARGET_GONE);
  CHECK_EQ(bgc_frame_live_count(), 0);
  bgc_window_snapshot snap;
  CHECK_EQ(bgc_snapshot(any, &snap), BGC_TARGET_GONE);
  CHECK_EQ(bgc_snapshot(any, nullptr), BGC_INVALID_ARGUMENT);
  CHECK_EQ(bgc_frame_info(0, nullptr), BGC_INVALID_ARGUMENT);
  return pass();
}

int g_real_signals = 0;
void count_signal() { g_real_signals++; }

Outcome real_hook_install_and_remove() {
  const uint16_t title[] = {'N', 'o', 'S', 'u', 'c', 'h', 'W', 'i', 'n', 0};
  uint32_t error = 0;
  CHECK_EQ(bgc_hook_start(title, count_signal, &error), BGC_OK);
  CHECK(hook_guard_held());
  CHECK_EQ(bgc_hook_start(title, count_signal, &error), BGC_ALREADY_STARTED);
  bgc_trigger_event out[BGC_RING_CAPACITY];
  uint32_t dropped = 0;
  CHECK_EQ(bgc_hook_drain(out, BGC_RING_CAPACITY, &dropped), 0);
  CHECK_EQ(bgc_hook_stop(), BGC_OK);
  CHECK(!hook_guard_held());
  CHECK_EQ(bgc_hook_stop(), BGC_NOT_STARTED);
  return pass();
}

const Case kCases[] = {
    {"guard_refuses_when_listing_contains_game",
     guard_refuses_when_listing_contains_game},
    {"capture_checks_skip_when_not_foreground",
     capture_checks_skip_when_not_foreground},
    {"filter_accepts_target_release_with_signed_point",
     filter_accepts_target_release_with_signed_point},
    {"filter_rejects_other_title", filter_rejects_other_title},
    {"filter_rejects_non_left_release_messages",
     filter_rejects_non_left_release_messages},
    {"filter_rejects_null_foreground", filter_rejects_null_foreground},
    {"filter_skips_own_process_without_title_read",
     filter_skips_own_process_without_title_read},
    {"hook_proc_always_calls_next_hook", hook_proc_always_calls_next_hook},
    {"append_returns_without_drain_and_keeps_order",
     append_returns_without_drain_and_keeps_order},
    {"ring_drops_oldest_and_reports_count", ring_drops_oldest_and_reports_count},
    {"signal_coalesces_until_drain", signal_coalesces_until_drain},
    {"append_after_drain_resignals", append_after_drain_resignals},
    {"install_failure_reports_error_and_ends_thread",
     install_failure_reports_error_and_ends_thread},
    {"all_zero_ignores_fourth_byte", all_zero_ignores_fourth_byte},
    {"all_zero_false_for_one_colour_byte", all_zero_false_for_one_colour_byte},
    {"registry_refuses_fifth_frame", registry_refuses_fifth_frame},
    {"exe_name_from_toolhelp_for_own_pid", exe_name_from_toolhelp_for_own_pid},
    {"abi_argument_validation", abi_argument_validation},
    {"real_hook_install_and_remove", real_hook_install_and_remove},
    {"captures_own_window_pattern_and_geometry",
     captures_own_window_pattern_and_geometry},
};

}  // namespace

int main() {
  // Game guard: first, before any hook, window or capture.
  std::vector<ProcessEntry> listing;
  DWORD list_error = 0;
  if (!list_processes_real(&listing, &list_error)) {
    printf("REFUSED: cannot list processes (error %lu); cannot confirm the game "
           "is not running\n",
           list_error);
    return 2;
  }
  std::wstring which;
  if (listing_has_game(listing, &which)) {
    wprintf(L"REFUSED: the game is running (%ls); the self-test refused to "
            L"start before installing any hook or capturing anything\n",
            which.c_str());
    return 2;
  }

  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

  int passed = 0, failed = 0, skipped = 0;
  for (const Case& c : kCases) {
    Outcome o = c.run();
    switch (o.kind) {
      case Kind::Pass:
        printf("PASS %s\n", c.name);
        passed++;
        break;
      case Kind::Fail:
        printf("FAIL %s: %s\n", c.name, o.reason.c_str());
        failed++;
        break;
      case Kind::Skip:
        printf("SKIP %s: %s\n", c.name, o.reason.c_str());
        skipped++;
        break;
    }
    fflush(stdout);
  }
  printf("SUMMARY pass=%d fail=%d skip=%d\n", passed, failed, skipped);
  return failed == 0 ? 0 : 1;
}
