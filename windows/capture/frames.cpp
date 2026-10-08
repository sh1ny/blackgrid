// Frame registry (design D7): four fixed slots, each a 32 bpp top-down DIB
// section. Ids are (slot << 32) | generation, so stale ids never match.
#include "capture_internal.h"

namespace bgc {

bool bgr_all_zero(const uint8_t* pixels, int width, int height, int stride) {
  if (pixels == nullptr || width <= 0 || height <= 0) return true;
  for (int y = 0; y < height; y++) {
    const uint8_t* row = pixels + static_cast<size_t>(y) * stride;
    int x = 0;
    // Two pixels per step; the mask drops each pixel's undefined fourth byte.
    for (; x + 2 <= width; x += 2) {
      uint64_t two;
      memcpy(&two, row + static_cast<size_t>(x) * 4, sizeof(two));
      if ((two & 0x00FFFFFF00FFFFFFull) != 0) return false;
    }
    for (; x < width; x++) {
      uint32_t one;
      memcpy(&one, row + static_cast<size_t>(x) * 4, sizeof(one));
      if ((one & 0x00FFFFFFu) != 0) return false;
    }
  }
  return true;
}

namespace {

bool dib_alloc(int width, int height, FrameMemory* out, DWORD* win32_error) {
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
  bi.bmiHeader.biWidth = width;
  bi.bmiHeader.biHeight = -height;  // negative: rows run top-down
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap =
      CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (bitmap == nullptr || bits == nullptr) {
    DWORD error = GetLastError();
    if (bitmap != nullptr) DeleteObject(bitmap);
    *win32_error = error != 0 ? error : ERROR_NOT_ENOUGH_MEMORY;
    return false;
  }
  out->bitmap = bitmap;
  out->bits = bits;
  return true;
}

void dib_free(FrameMemory* memory) {
  if (memory->bitmap != nullptr) DeleteObject(memory->bitmap);
  memory->bitmap = nullptr;
  memory->bits = nullptr;
}

bool decode(uint64_t id, uint32_t* slot, uint32_t* generation) {
  *slot = static_cast<uint32_t>(id >> 32);
  *generation = static_cast<uint32_t>(id & 0xFFFFFFFFu);
  return *slot < BGC_FRAME_SLOTS && *generation != 0;
}

}  // namespace

FrameAllocFn real_frame_alloc() { return dib_alloc; }
FrameFreeFn real_frame_free() { return dib_free; }

void registry_init(Registry& reg, FrameAllocFn alloc, FrameFreeFn free_memory) {
  reg.alloc = alloc;
  reg.free_memory = free_memory;
}

uint64_t registry_reserve(Registry& reg) {
  uint64_t id = 0;
  AcquireSRWLockExclusive(&reg.lock);
  for (uint32_t i = 0; i < BGC_FRAME_SLOTS; i++) {
    Registry::Slot& slot = reg.slots[i];
    if (slot.live) continue;
    slot.generation++;
    if (slot.generation == 0) slot.generation = 1;  // never 0
    slot.live = true;
    slot.ready = false;
    id = (static_cast<uint64_t>(i) << 32) | slot.generation;
    break;
  }
  ReleaseSRWLockExclusive(&reg.lock);
  return id;
}

bool registry_allocate(Registry& reg, uint64_t id, int width, int height,
                       DWORD* win32_error) {
  uint32_t index, generation;
  if (!decode(id, &index, &generation)) return false;
  AcquireSRWLockShared(&reg.lock);
  const Registry::Slot& check = reg.slots[index];
  bool reserved = check.live && !check.ready && check.generation == generation;
  ReleaseSRWLockShared(&reg.lock);
  if (!reserved) return false;

  FrameMemory memory;
  DWORD error = 0;
  // The (possibly large) allocation happens outside the lock.
  if (!reg.alloc(width, height, &memory, &error)) {
    if (win32_error != nullptr) *win32_error = error;
    return false;
  }
  bool attached = false;
  AcquireSRWLockExclusive(&reg.lock);
  Registry::Slot& slot = reg.slots[index];
  if (slot.live && !slot.ready && slot.generation == generation) {
    slot.memory = memory;
    slot.width = width;
    slot.height = height;
    slot.stride = width * 4;
    slot.ready = true;
    attached = true;
  }
  ReleaseSRWLockExclusive(&reg.lock);
  if (!attached) {
    reg.free_memory(&memory);
    if (win32_error != nullptr) *win32_error = ERROR_INVALID_HANDLE;
  }
  return attached;
}

void registry_release(Registry& reg, uint64_t id) {
  uint32_t index, generation;
  if (!decode(id, &index, &generation)) return;
  FrameMemory memory;
  bool had_memory = false;
  AcquireSRWLockExclusive(&reg.lock);
  Registry::Slot& slot = reg.slots[index];
  if (slot.live && slot.generation == generation) {
    had_memory = slot.ready;
    memory = slot.memory;
    slot.memory = FrameMemory();
    slot.live = false;
    slot.ready = false;
    slot.width = slot.height = slot.stride = 0;
  }
  ReleaseSRWLockExclusive(&reg.lock);
  if (had_memory) reg.free_memory(&memory);
}

bool registry_info(Registry& reg, uint64_t id, bgc_frame_view* out,
                   HBITMAP* bitmap) {
  uint32_t index, generation;
  if (!decode(id, &index, &generation)) return false;
  bool ok = false;
  AcquireSRWLockShared(&reg.lock);
  const Registry::Slot& slot = reg.slots[index];
  if (slot.live && slot.ready && slot.generation == generation) {
    if (out != nullptr) {
      out->pixels = static_cast<uint8_t*>(slot.memory.bits);
      out->width = slot.width;
      out->height = slot.height;
      out->stride = slot.stride;
      out->reserved = 0;
    }
    if (bitmap != nullptr) *bitmap = slot.memory.bitmap;
    ok = true;
  }
  ReleaseSRWLockShared(&reg.lock);
  return ok;
}

uint32_t registry_live_count(Registry& reg) {
  uint32_t live = 0;
  AcquireSRWLockShared(&reg.lock);
  for (const Registry::Slot& slot : reg.slots) {
    if (slot.live) live++;
  }
  ReleaseSRWLockShared(&reg.lock);
  return live;
}

Registry& global_registry() {
  static Registry* reg = [] {
    Registry* r = new Registry();
    registry_init(*r, dib_alloc, dib_free);
    return r;
  }();
  return *reg;
}

}  // namespace bgc
