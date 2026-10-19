// Native unit test for the input thread's trigger and hotkey logic. Everything
// goes through injected environments and fakes: it opens no real window, hook,
// hotkey or capture, so it needs no game gate (selftest.cpp holds the real-OS
// cases). Every case prints PASS / FAIL; the exit code is 0 only when nothing
// FAILed.
#include "capture_internal.h"

#include <stdio.h>
#include <string.h>
#include <wchar.h>

#include <string>
#include <thread>
#include <vector>

namespace {

using namespace bgc;

// --- Harness -----------------------------------------------------------------

struct Outcome {
  bool ok;
  std::string reason;
};
Outcome pass() { return {true, ""}; }
Outcome fail(const std::string& reason) { return {false, reason}; }

std::string at(int line) {
  return " (unittest.cpp:" + std::to_string(line) + ")";
}

#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) return fail(std::string(#cond) + at(__LINE__)); \
  } while (0)

#define CHECK_EQ(actual, expected)                                  \
  do {                                                              \
    long long a_ = (long long)(actual);                             \
    long long e_ = (long long)(expected);                           \
    if (a_ != e_)                                                   \
      return fail(std::string(#actual " = " + std::to_string(a_) +  \
                              ", expected " + std::to_string(e_)) + \
                  at(__LINE__));                                    \
  } while (0)

struct Case {
  const char* name;
  Outcome (*run)();
};

// --- Environment fakes -----------------------------------------------------------

const wchar_t kTarget[] = L"EscapeFromTarkov";
const HWND kFakeWindow = reinterpret_cast<HWND>(static_cast<uintptr_t>(0x1234));
const uint32_t kOwnPid = 100;
const uint32_t kVkF9 = 0x78;
const uint32_t kVkF10 = 0x79;

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

HWND g_foreground = nullptr;
uint32_t g_pid = 500;
uint32_t g_tid = 77;
POINT g_cursor = {640, 360};
bool g_cursor_ok = true;
int64_t g_qpc = 424242;
int g_next_calls = 0;
int g_post_calls = 0;
int g_signal_calls = 0;
DWORD g_signal_thread = 0;

void reset_fakes() {
  g_foreground = kFakeWindow;
  g_pid = 500;
  g_tid = 77;
  g_cursor = {640, 360};
  g_cursor_ok = true;
  g_qpc = 424242;
  g_next_calls = 0;
  g_post_calls = 0;
  g_signal_calls = 0;
  g_signal_thread = 0;
}

HWND fake_foreground() { return g_foreground; }
uint32_t fake_window_pid(HWND, uint32_t* tid) {
  *tid = g_tid;
  return g_pid;
}
bool fake_cursor(POINT* out) {
  *out = g_cursor;
  return g_cursor_ok;
}
LRESULT fake_call_next(int, WPARAM, LPARAM) {
  g_next_calls++;
  return 777;
}
void fake_post_signal() { g_post_calls++; }
void fake_signal() {
  g_signal_calls++;
  g_signal_thread = GetCurrentThreadId();
}
int64_t fake_qpc() { return g_qpc; }

HookEnv make_mouse_env(TitleFake* title) {
  HookEnv env = {};
  env.foreground = fake_foreground;
  env.window_pid = fake_window_pid;
  env.read_title = fake_read_title;
  env.title_ctx = title;
  env.call_next = fake_call_next;
  env.post_signal = fake_post_signal;
  env.qpc = fake_qpc;
  env.own_pid = kOwnPid;
  return env;
}

HotkeyEnv make_hotkey_env(TitleFake* title) {
  HotkeyEnv env = {};
  env.foreground = fake_foreground;
  env.window_pid = fake_window_pid;
  env.read_title = fake_read_title;
  env.title_ctx = title;
  env.cursor = fake_cursor;
  env.signal = fake_signal;
  env.qpc = fake_qpc;
  env.own_pid = kOwnPid;
  return env;
}

uint32_t drain(Ring& ring, bgc_trigger_event* out, uint32_t* dropped) {
  return ring_drain(ring, out, BGC_RING_CAPACITY, dropped);
}

void mouse_release(const HookEnv& env, Ring& ring, int32_t x, int32_t y) {
  MSLLHOOKSTRUCT info = {};
  info.pt.x = x;
  info.pt.y = y;
  hook_proc_core(env, ring, kTarget, 0, WM_LBUTTONUP,
                 reinterpret_cast<LPARAM>(&info));
}

// --- Hotkey registrar fake ---------------------------------------------------------

struct Call {
  char kind;  // 'R' register, 'U' unregister, 'H' uninstall of the mouse hook
  int id;
  uint32_t modifiers;
  uint32_t vk;
};
std::vector<Call> g_calls;
struct Refusal {
  uint32_t vk;
  DWORD error;
};
std::vector<Refusal> g_refused;
void (*g_on_register)() = nullptr;

void reset_registrar() {
  g_calls.clear();
  g_refused.clear();
  g_on_register = nullptr;
}

bool fake_register(int id, uint32_t modifiers, uint32_t vk, DWORD* error) {
  g_calls.push_back({'R', id, modifiers, vk});
  if (g_on_register != nullptr) g_on_register();
  for (const Refusal& r : g_refused) {
    if (r.vk == vk) {
      *error = r.error;
      return false;
    }
  }
  return true;
}
void fake_unregister(int id) { g_calls.push_back({'U', id, 0, 0}); }
const HotkeyRegistrar kFakeRegistrar = {fake_register, fake_unregister};

HHOOK fake_install(HOOKPROC, DWORD*) {
  return reinterpret_cast<HHOOK>(static_cast<uintptr_t>(1));
}
void fake_uninstall(HHOOK) { g_calls.push_back({'H', 0, 0, 0}); }
const HookInstaller kFakeInstaller = {fake_install, fake_uninstall};

int count_calls(char kind) {
  int n = 0;
  for (const Call& c : g_calls) {
    if (c.kind == kind) n++;
  }
  return n;
}

// The "input thread" answers synchronously from inside the post, so a request
// completes before its caller starts to wait.
struct Rig {
  HotkeySlot slot;
  HotkeyState state;
};
bool post_and_answer(void* ctx) {
  Rig* rig = static_cast<Rig*>(ctx);
  hotkey_service(rig->slot, kFakeRegistrar, rig->state);
  return true;
}
int32_t set_key(Rig& rig, uint32_t vk, uint32_t* error = nullptr) {
  return hotkey_request(rig.slot, true, post_and_answer, &rig, vk, 1000, error);
}

// A post that records the request and never answers it.
int g_unanswered_posts = 0;
bool post_unanswered(void*) {
  g_unanswered_posts++;
  return true;
}

// --- Hotkey target facts ---------------------------------------------------------

Outcome hotkey_press_over_target_window() {
  reset_fakes();
  TitleFake title = {kTarget, 0};
  Ring ring;
  HotkeyEnv env = make_hotkey_env(&title);
  CHECK(hotkey_core(env, ring, kTarget));
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 99;
  CHECK_EQ(drain(ring, out, &dropped), 1);
  CHECK_EQ(dropped, 0);
  CHECK_EQ(out[0].source, BGC_TRIGGER_HOTKEY);
  CHECK_EQ(out[0].x, 640);
  CHECK_EQ(out[0].y, 360);
  CHECK_EQ(out[0].hwnd, 0x1234);
  CHECK_EQ(out[0].pid, 500);
  CHECK_EQ(out[0].tid, 77);
  CHECK_EQ(out[0].qpc, 424242);
  return pass();
}

Outcome hotkey_press_over_another_window() {
  reset_fakes();
  TitleFake title = {L"Notepad", 0};
  Ring ring;
  HotkeyEnv env = make_hotkey_env(&title);
  CHECK(!hotkey_core(env, ring, kTarget));
  CHECK_EQ(title.calls, 1);
  CHECK_EQ(g_signal_calls, 0);
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(drain(ring, out, &dropped), 0);

  // No foreground window at all.
  g_foreground = nullptr;
  g_pid = 0;
  TitleFake none = {kTarget, 0};
  HotkeyEnv env_none = make_hotkey_env(&none);
  CHECK(!hotkey_core(env_none, ring, kTarget));
  CHECK_EQ(none.calls, 0);
  CHECK_EQ(drain(ring, out, &dropped), 0);
  return pass();
}

Outcome hotkey_press_over_blackgrid() {
  reset_fakes();
  g_pid = kOwnPid;  // the foreground window is ours
  TitleFake title = {kTarget, 0};
  Ring ring;
  HotkeyEnv env = make_hotkey_env(&title);
  CHECK(!hotkey_core(env, ring, kTarget));
  CHECK_EQ(title.calls, 0);  // our own windows are never read
  CHECK_EQ(g_signal_calls, 0);
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(drain(ring, out, &dropped), 0);
  return pass();
}

Outcome hook_mouse_release_keeps_its_source() {
  reset_fakes();
  TitleFake title = {kTarget, 0};
  Ring ring;
  HookEnv env = make_mouse_env(&title);
  mouse_release(env, ring, -1200, 340);
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(drain(ring, out, &dropped), 1);
  CHECK_EQ(out[0].source, BGC_TRIGGER_MOUSE);
  CHECK_EQ(out[0].x, -1200);
  CHECK_EQ(out[0].reserved, 0);
  CHECK_EQ(sizeof(bgc_trigger_event), 40);
  CHECK_EQ(offsetof(bgc_trigger_event, source), 32);
  return pass();
}

// --- No repeat -------------------------------------------------------------------

Outcome swap_registers_with_norepeat_and_no_modifier() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  CHECK_EQ(g_calls.size(), 1);
  CHECK_EQ(g_calls[0].kind, 'R');
  CHECK_EQ(g_calls[0].modifiers, MOD_NOREPEAT);  // and no other modifier bit
  CHECK_EQ(g_calls[0].vk, kVkF9);
  return pass();
}

Outcome hotkey_two_presses_append_two_events_in_order() {
  reset_fakes();
  TitleFake title = {kTarget, 0};
  Ring ring;
  HotkeyEnv env = make_hotkey_env(&title);
  g_qpc = 1000;
  g_cursor = {10, 20};
  CHECK(hotkey_core(env, ring, kTarget));
  g_qpc = 2000;
  g_cursor = {30, 40};
  CHECK(hotkey_core(env, ring, kTarget));
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(drain(ring, out, &dropped), 2);
  CHECK_EQ(out[0].qpc, 1000);
  CHECK_EQ(out[0].x, 10);
  CHECK_EQ(out[1].qpc, 2000);
  CHECK_EQ(out[1].x, 30);
  CHECK_EQ(out[0].source, BGC_TRIGGER_HOTKEY);
  CHECK_EQ(out[1].source, BGC_TRIGGER_HOTKEY);
  return pass();
}

// --- Shared queue ------------------------------------------------------------------

Outcome ring_mixed_sources_drain_in_append_order() {
  reset_fakes();
  TitleFake title = {kTarget, 0};
  Ring ring;
  HookEnv mouse = make_mouse_env(&title);
  HotkeyEnv hotkey = make_hotkey_env(&title);
  g_qpc = 1;
  mouse_release(mouse, ring, 1, 1);
  g_qpc = 2;
  CHECK(hotkey_core(hotkey, ring, kTarget));
  g_qpc = 3;
  mouse_release(mouse, ring, 3, 3);
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 99;
  CHECK_EQ(drain(ring, out, &dropped), 3);
  CHECK_EQ(dropped, 0);
  CHECK_EQ(out[0].source, BGC_TRIGGER_MOUSE);
  CHECK_EQ(out[1].source, BGC_TRIGGER_HOTKEY);
  CHECK_EQ(out[2].source, BGC_TRIGGER_MOUSE);
  CHECK_EQ(out[0].qpc, 1);
  CHECK_EQ(out[1].qpc, 2);
  CHECK_EQ(out[2].qpc, 3);
  return pass();
}

Outcome hotkey_press_appends_and_signals_without_waiting() {
  reset_fakes();
  TitleFake title = {kTarget, 0};
  Ring ring;
  HotkeyEnv env = make_hotkey_env(&title);  // has no post path at all
  CHECK(hotkey_core(env, ring, kTarget));
  // The append ran on the thread that delivers signals, so it calls the signal
  // itself, once, and returns without waiting for anything.
  CHECK_EQ(g_signal_calls, 1);
  CHECK_EQ(g_signal_thread, GetCurrentThreadId());
  CHECK(ring_signal_pending(ring));
  CHECK_EQ(g_post_calls, 0);
  // Coalesced until a drain, as for the mouse source.
  CHECK(hotkey_core(env, ring, kTarget));
  CHECK_EQ(g_signal_calls, 1);
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(drain(ring, out, &dropped), 2);
  CHECK(hotkey_core(env, ring, kTarget));
  CHECK_EQ(g_signal_calls, 2);
  return pass();
}

Outcome ring_overflow_across_sources_keeps_newest_16_and_counts_4() {
  reset_fakes();
  TitleFake title = {kTarget, 0};
  Ring ring;
  HookEnv mouse = make_mouse_env(&title);
  HotkeyEnv hotkey = make_hotkey_env(&title);
  for (int32_t i = 0; i < 20; i++) {
    g_qpc = 100 + i;
    if (i % 2 == 0) {
      mouse_release(mouse, ring, i, i);
    } else {
      g_cursor = {i, i};
      CHECK(hotkey_core(hotkey, ring, kTarget));
    }
  }
  bgc_trigger_event out[BGC_RING_CAPACITY] = {};
  uint32_t dropped = 0;
  CHECK_EQ(drain(ring, out, &dropped), 16);
  CHECK_EQ(dropped, 4);
  for (int32_t i = 0; i < 16; i++) {
    int32_t n = i + 4;
    CHECK_EQ(out[i].x, n);
    CHECK_EQ(out[i].qpc, 100 + n);
    CHECK_EQ(out[i].source, n % 2 == 0 ? BGC_TRIGGER_MOUSE : BGC_TRIGGER_HOTKEY);
  }
  return pass();
}

// --- Registration ------------------------------------------------------------------

Outcome swap_register_a_free_key() {
  reset_registrar();
  Rig rig;
  uint32_t error = 99;
  CHECK_EQ(set_key(rig, kVkF9, &error), BGC_OK);
  CHECK_EQ(error, 0);
  CHECK(rig.state.active != 0);
  CHECK_EQ(rig.state.vk[rig.state.active], kVkF9);
  CHECK_EQ(count_calls('R'), 1);
  CHECK_EQ(count_calls('U'), 0);
  return pass();
}

Outcome swap_key_held_elsewhere_returns_unavailable_with_the_os_code() {
  reset_registrar();
  g_refused.push_back({kVkF9, ERROR_HOTKEY_ALREADY_REGISTERED});
  Rig rig;
  uint32_t error = 0;
  CHECK_EQ(set_key(rig, kVkF9, &error), BGC_HOTKEY_UNAVAILABLE);
  CHECK_EQ(error, ERROR_HOTKEY_ALREADY_REGISTERED);
  CHECK_EQ(rig.state.active, 0);
  CHECK_EQ(rig.state.vk[1], 0);
  CHECK_EQ(rig.state.vk[2], 0);
  CHECK_EQ(count_calls('U'), 0);
  return pass();
}

Outcome api_hotkey_set_while_stopped_returns_not_started() {
  reset_registrar();
  Rig rig;
  g_unanswered_posts = 0;
  uint32_t error = 99;
  CHECK_EQ(hotkey_request(rig.slot, false, post_unanswered, nullptr, kVkF9,
                          1000, &error),
           BGC_NOT_STARTED);
  CHECK_EQ(error, 0);
  CHECK_EQ(g_unanswered_posts, 0);
  CHECK_EQ(g_calls.size(), 0);
  CHECK_EQ(rig.state.active, 0);
  return pass();
}

Outcome api_unsupported_key_returns_invalid_argument() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  const size_t before = g_calls.size();
  const uint32_t bad[] = {1, 0x41, 0x6F, 0x88, 0x2E, 0x100, 0xFFFFFFFFu};
  for (uint32_t vk : bad) {
    CHECK_EQ(set_key(rig, vk), BGC_INVALID_ARGUMENT);
  }
  CHECK_EQ(g_calls.size(), before);  // the registration is unchanged
  CHECK_EQ(rig.state.vk[rig.state.active], kVkF9);
  // The accepted range is off plus F1..F24 and nothing else.
  CHECK(hotkey_vk_valid(0));
  CHECK(hotkey_vk_valid(0x70));
  CHECK(hotkey_vk_valid(0x87));
  CHECK(!hotkey_vk_valid(0x6F));
  CHECK(!hotkey_vk_valid(0x88));
  // A stopped source still reports the argument error first.
  CHECK_EQ(hotkey_request(rig.slot, false, post_unanswered, nullptr, 0x41, 1000,
                          nullptr),
           BGC_INVALID_ARGUMENT);
  return pass();
}

Outcome swap_off_unregisters() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  const int held = rig.state.active;
  CHECK_EQ(set_key(rig, 0), BGC_OK);
  CHECK_EQ(g_calls.size(), 2);
  CHECK_EQ(g_calls[1].kind, 'U');
  CHECK_EQ(g_calls[1].id, held);
  CHECK_EQ(rig.state.active, 0);
  CHECK_EQ(rig.state.vk[held], 0);
  // Off again is a no-op success.
  CHECK_EQ(set_key(rig, 0), BGC_OK);
  CHECK_EQ(g_calls.size(), 2);
  return pass();
}

// --- Rebinding -----------------------------------------------------------------------

Outcome swap_rebind_registers_new_before_releasing_old() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  const int a = rig.state.active;
  CHECK_EQ(set_key(rig, kVkF10), BGC_OK);
  CHECK_EQ(g_calls.size(), 3);
  CHECK_EQ(g_calls[1].kind, 'R');
  CHECK_EQ(g_calls[1].vk, kVkF10);
  CHECK(g_calls[1].id != a);  // the id the old key is not using
  CHECK_EQ(g_calls[1].modifiers, MOD_NOREPEAT);
  CHECK_EQ(g_calls[2].kind, 'U');
  CHECK_EQ(g_calls[2].id, a);
  CHECK_EQ(rig.state.active, g_calls[1].id);
  CHECK_EQ(rig.state.vk[a], 0);
  return pass();
}

Outcome swap_refused_rebind_keeps_the_old_key() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  const int a = rig.state.active;
  g_refused.push_back({kVkF10, ERROR_HOTKEY_ALREADY_REGISTERED});
  uint32_t error = 0;
  CHECK_EQ(set_key(rig, kVkF10, &error), BGC_HOTKEY_UNAVAILABLE);
  CHECK_EQ(error, ERROR_HOTKEY_ALREADY_REGISTERED);
  CHECK_EQ(rig.state.active, a);
  CHECK_EQ(rig.state.vk[a], kVkF9);
  CHECK_EQ(count_calls('U'), 0);  // the old key was never released
  return pass();
}

Outcome swap_same_key_is_a_no_op() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  const size_t before = g_calls.size();
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  CHECK_EQ(g_calls.size(), before);  // no register, no unregister
  return pass();
}

Outcome request_timeout_reserves_the_slot_until_answered() {
  reset_registrar();
  Rig rig;
  g_unanswered_posts = 0;
  CHECK_EQ(hotkey_request(rig.slot, true, post_unanswered, nullptr, kVkF9, 20,
                          nullptr),
           BGC_HOTKEY_TIMED_OUT);
  CHECK_EQ(g_unanswered_posts, 1);
  // Reserved: refused at once, without reaching the thread.
  CHECK_EQ(hotkey_request(rig.slot, true, post_unanswered, nullptr, kVkF10, 20,
                          nullptr),
           BGC_HOTKEY_TIMED_OUT);
  CHECK_EQ(g_unanswered_posts, 1);
  // The thread finally picks the abandoned request up: it changes nothing and
  // frees the slot.
  hotkey_service(rig.slot, kFakeRegistrar, rig.state);
  CHECK_EQ(g_calls.size(), 0);
  CHECK_EQ(hotkey_request(rig.slot, true, post_unanswered, nullptr, kVkF10, 20,
                          nullptr),
           BGC_HOTKEY_TIMED_OUT);
  CHECK_EQ(g_unanswered_posts, 2);  // this one did reach the thread
  return pass();
}

// Gates for the late-answer cases: explicit signals, no sleeps.
HANDLE g_posted = nullptr;
HANDLE g_gate = nullptr;
bool post_signal_posted(void*) {
  SetEvent(g_posted);
  return true;
}
void wait_for_gate() { WaitForSingleObject(g_gate, 5000); }

struct Requester {
  Rig* rig;
  uint32_t vk;
  uint32_t timeout_ms;
  int32_t status;
  uint32_t error;
};
void run_requester(Requester* r) {
  r->status = hotkey_request(r->rig->slot, true, post_signal_posted, nullptr,
                             r->vk, r->timeout_ms, &r->error);
  SetEvent(g_gate);  // the caller has timed out; the thread may now go on
}

Outcome request_abandoned_swap_releases_only_the_new_key() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  const int a = rig.state.active;
  g_calls.clear();

  g_posted = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_gate = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  Requester req = {&rig, kVkF10, 30, 0, 0};
  std::thread caller(run_requester, &req);
  WaitForSingleObject(g_posted, 5000);
  // The thread registers F10 only after the caller has given up waiting.
  g_on_register = wait_for_gate;
  hotkey_service(rig.slot, kFakeRegistrar, rig.state);
  caller.join();
  g_on_register = nullptr;
  CloseHandle(g_posted);
  CloseHandle(g_gate);

  CHECK_EQ(req.status, BGC_HOTKEY_TIMED_OUT);
  CHECK_EQ(g_calls.size(), 2);
  CHECK_EQ(g_calls[0].kind, 'R');
  CHECK_EQ(g_calls[0].vk, kVkF10);
  const int b = g_calls[0].id;
  CHECK(b != a);
  CHECK_EQ(g_calls[1].kind, 'U');
  CHECK_EQ(g_calls[1].id, b);  // only the new key was released
  CHECK_EQ(rig.state.active, a);
  CHECK_EQ(rig.state.vk[a], kVkF9);  // F9 was never re-registered or released
  CHECK_EQ(rig.state.vk[b], 0);

  // The slot is free again: the next request reaches the thread and works.
  CHECK_EQ(set_key(rig, kVkF10), BGC_OK);
  CHECK_EQ(rig.state.vk[rig.state.active], kVkF10);
  return pass();
}

Outcome request_abandoned_off_keeps_the_current_key() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  const int a = rig.state.active;
  g_calls.clear();

  // Abandoned before the thread picks it up: nothing happens at all.
  g_unanswered_posts = 0;
  CHECK_EQ(hotkey_request(rig.slot, true, post_unanswered, nullptr, 0, 20,
                          nullptr),
           BGC_HOTKEY_TIMED_OUT);
  hotkey_service(rig.slot, kFakeRegistrar, rig.state);
  CHECK_EQ(g_calls.size(), 0);
  CHECK_EQ(rig.state.active, a);

  // Abandoned while the thread is already working on it.
  g_posted = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_gate = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  Requester req = {&rig, 0, 30, 0, 0};
  std::thread caller(run_requester, &req);
  WaitForSingleObject(g_posted, 5000);
  WaitForSingleObject(g_gate, 5000);  // caller has timed out
  caller.join();
  hotkey_service(rig.slot, kFakeRegistrar, rig.state);
  CloseHandle(g_posted);
  CloseHandle(g_gate);
  CHECK_EQ(req.status, BGC_HOTKEY_TIMED_OUT);
  CHECK_EQ(g_calls.size(), 0);  // the current key is not released
  CHECK_EQ(rig.state.active, a);
  CHECK_EQ(rig.state.vk[a], kVkF9);
  return pass();
}

// --- Stop --------------------------------------------------------------------------------

Outcome thread_exit_unregisters_every_hotkey_id_and_completes_a_pending_request() {
  reset_registrar();
  Rig rig;
  CHECK_EQ(set_key(rig, kVkF9), BGC_OK);
  rig.state.vk[rig.state.active == 1 ? 2 : 1] = kVkF10;  // both ids are held
  g_calls.clear();

  g_posted = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_gate = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  Requester req = {&rig, kVkF10, 5000, 0, 0};  // the thread never answers it
  std::thread caller(run_requester, &req);
  WaitForSingleObject(g_posted, 5000);

  hotkey_teardown(rig.slot, kFakeRegistrar, rig.state, kFakeInstaller,
                  reinterpret_cast<HHOOK>(static_cast<uintptr_t>(1)));
  caller.join();
  CloseHandle(g_posted);
  CloseHandle(g_gate);

  CHECK_EQ(req.status, BGC_NOT_STARTED);
  CHECK_EQ(g_calls.size(), 3);
  CHECK_EQ(g_calls[0].kind, 'U');
  CHECK_EQ(g_calls[1].kind, 'U');
  CHECK(g_calls[0].id != g_calls[1].id);
  CHECK_EQ(g_calls[2].kind, 'H');  // both keys are gone before the unhook
  CHECK_EQ(rig.state.active, 0);
  CHECK_EQ(rig.state.vk[1], 0);
  CHECK_EQ(rig.state.vk[2], 0);
  return pass();
}

const std::vector<Case> kCases = {
    {"hotkey: press over the target window", hotkey_press_over_target_window},
    {"hotkey: press over another window", hotkey_press_over_another_window},
    {"hotkey: press over blackgrid", hotkey_press_over_blackgrid},
    {"hook: mouse release keeps its source", hook_mouse_release_keeps_its_source},
    {"swap: registers with MOD_NOREPEAT and no modifier",
     swap_registers_with_norepeat_and_no_modifier},
    {"hotkey: two presses append two events in order",
     hotkey_two_presses_append_two_events_in_order},
    {"ring: mixed sources drain in append order",
     ring_mixed_sources_drain_in_append_order},
    {"hotkey: press appends and signals without waiting",
     hotkey_press_appends_and_signals_without_waiting},
    {"ring: overflow across sources keeps newest 16 and counts 4",
     ring_overflow_across_sources_keeps_newest_16_and_counts_4},
    {"swap: register a free key", swap_register_a_free_key},
    {"swap: key held elsewhere returns unavailable with the os code",
     swap_key_held_elsewhere_returns_unavailable_with_the_os_code},
    {"api: hotkey set while stopped returns not started",
     api_hotkey_set_while_stopped_returns_not_started},
    {"api: unsupported key returns invalid argument",
     api_unsupported_key_returns_invalid_argument},
    {"swap: off unregisters", swap_off_unregisters},
    {"swap: rebind registers new before releasing old",
     swap_rebind_registers_new_before_releasing_old},
    {"swap: refused rebind keeps the old key",
     swap_refused_rebind_keeps_the_old_key},
    {"swap: same key is a no-op", swap_same_key_is_a_no_op},
    {"request: timeout reserves the slot until answered",
     request_timeout_reserves_the_slot_until_answered},
    {"request: abandoned swap releases only the new key",
     request_abandoned_swap_releases_only_the_new_key},
    {"request: abandoned off keeps the current key",
     request_abandoned_off_keeps_the_current_key},
    {"thread exit unregisters every hotkey id and completes a pending request",
     thread_exit_unregisters_every_hotkey_id_and_completes_a_pending_request},
};

}  // namespace

int main() {
  int passed = 0, failed = 0;
  for (const Case& c : kCases) {
    Outcome o = c.run();
    if (o.ok) {
      printf("PASS %s\n", c.name);
      passed++;
    } else {
      printf("FAIL %s: %s\n", c.name, o.reason.c_str());
      failed++;
    }
    fflush(stdout);
  }
  printf("SUMMARY pass=%d fail=%d\n", passed, failed);
  return failed == 0 ? 0 : 1;
}
