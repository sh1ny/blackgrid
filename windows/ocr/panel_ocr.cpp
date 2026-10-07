// Map-owned saved-image primitives over the OS Windows.Media.Ocr engine.
// Panel detection, parsing and current-map matching stay in Dart.
#define NOMINMAX
#include <windows.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
namespace imaging = winrt::Windows::Graphics::Imaging;
namespace ocr = winrt::Windows::Media::Ocr;
#define BG_API extern "C" __declspec(dllexport)
struct BgWord {
  int32_t left, top, right, bottom;
  int32_t line;
  const char* text;
};
struct Word {
  int32_t left, top, right, bottom;
  int32_t line;
  std::string text;
};
struct Engine {
  std::unique_ptr<uint8_t[]> rgba;
  size_t rgba_capacity = 0;
  std::vector<Word> words;
  std::string text;
  int width = 0, height = 0;
};
// Dart isolates may move between OS threads. Join the MTA for each
// synchronous native call; every WinRT object lives within that call.
// C++/WinRT caches activation factories process-wide, so the MTA itself must
// outlive any one call: hold one process-lifetime MTA usage.
struct Apartment {
  HRESULT status = Enter();
  ~Apartment() { if (SUCCEEDED(status)) CoUninitialize(); }
  static HRESULT Enter() {
    static const HRESULT keep_alive = [] {
      CO_MTA_USAGE_COOKIE cookie = nullptr;
      return CoIncrementMTAUsage(&cookie);
    }();
    if (FAILED(keep_alive)) return keep_alive;
    return CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  }
};
static ocr::OcrEngine CreateOcr() {
  auto engine = ocr::OcrEngine::TryCreateFromLanguage(
    winrt::Windows::Globalization::Language(L"en-US"));
  return engine ? engine : ocr::OcrEngine::TryCreateFromUserProfileLanguages();
}
// Same text-colour classes as the reference parser: light UI text, green
// header/available text and red unavailable text become black on white.
static bool LikelyPanelText(int r, int g, int b) {
  const int max = std::max({r, g, b}), min = std::min({r, g, b});
  return (max >= 165 && max - min <= 90) ||
    (g >= 140 && g >= r + 25 && g >= b + 10) ||
    (r >= 145 && r >= g + 25 && r >= b + 20);
}
BG_API uint32_t bg_ocr_abi() { return 2; }
BG_API void* bg_ocr_alloc(uint32_t size) { return size <= 64u * 1024 * 1024 ? std::malloc(size) : nullptr; }
BG_API void bg_ocr_free(void* ptr) { std::free(ptr); }
// Null when no OS recognizer language is installed.
BG_API Engine* bg_ocr_create() {
  try {
    Apartment apartment;
    if (FAILED(apartment.status) || !CreateOcr()) return nullptr;
    return new Engine();
  } catch (...) { return nullptr; }
}
BG_API void bg_ocr_destroy(Engine* engine) { delete engine; }
BG_API void bg_ocr_clear(Engine* engine) {
  if (!engine) return;
  // Retain bounded decode capacity for repeated saved-image jobs. Engine
  // destruction releases it. Maximum decoded capacity is 96 MiB.
  engine->words.clear();
  engine->text.clear();
  engine->width = engine->height = 0;
}
// Status: 0 success, 1 input/bounds, 2 decode, 3 recognition,
// 4 allocation/native failure, 5 OCR language unavailable.
BG_API int32_t bg_ocr_decode(Engine* engine, uint8_t* bytes, uint32_t size) {
  if (!engine || !bytes || !size || size > 64u * 1024 * 1024) return 1;
  bg_ocr_clear(engine);
  try {
    Apartment apartment;
    if (FAILED(apartment.status)) return 2;
    ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.GetAddressOf()));
    if (FAILED(hr)) return 2;
    ComPtr<IWICStream> stream;
    ComPtr<IWICBitmapDecoder> decoder;
    ComPtr<IWICBitmapFrameDecode> frame;
    ComPtr<IWICFormatConverter> converter;
    hr = factory->CreateStream(stream.GetAddressOf());
    if (FAILED(hr)) return 2;
    hr = stream->InitializeFromMemory(bytes, size);
    if (FAILED(hr)) return 2;
    hr = factory->CreateDecoderFromStream(stream.Get(), nullptr,
      WICDecodeMetadataCacheOnDemand, decoder.GetAddressOf());
    if (FAILED(hr)) return 2;
    GUID format;
    if (FAILED(decoder->GetContainerFormat(&format)) ||
        (!IsEqualGUID(format, GUID_ContainerFormatPng) && !IsEqualGUID(format, GUID_ContainerFormatJpeg))) return 2;
    UINT frames = 0, width = 0, height = 0;
    if (FAILED(decoder->GetFrameCount(&frames)) || frames != 1 ||
        FAILED(decoder->GetFrame(0, frame.GetAddressOf())) ||
        FAILED(frame->GetSize(&width, &height))) return 2;
    if (!width || !height || width > 8192 || height > 8192 ||
        static_cast<uint64_t>(width) * height > 24u * 1024 * 1024) return 1;
    hr = factory->CreateFormatConverter(converter.GetAddressOf());
    if (FAILED(hr)) return 2;
    hr = converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppRGBA,
      WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) return 2;
    const size_t decoded_size = static_cast<size_t>(width) * height * 4;
    if (engine->rgba_capacity < decoded_size) {
      engine->rgba.reset(new uint8_t[decoded_size]);
      engine->rgba_capacity = decoded_size;
    }
    hr = converter->CopyPixels(nullptr, width * 4,
      static_cast<UINT>(decoded_size), engine->rgba.get());
    if (FAILED(hr)) { bg_ocr_clear(engine); return 2; }
    engine->width = static_cast<int>(width);
    engine->height = static_cast<int>(height);
    return 0;
  } catch (...) { bg_ocr_clear(engine); return 4; }
}
// Recognizes one decoded region, upscaled by scale_milli/1000 with high
// quality bicubic interpolation and optionally binarized. Word boxes are
// returned in original image coordinates.
BG_API int32_t bg_ocr_recognize(Engine* engine, int32_t left, int32_t top,
    int32_t right, int32_t bottom, int32_t scale_milli, int32_t enhance) {
  if (!engine || left < 0 || top < 0 || right > engine->width ||
      bottom > engine->height || right <= left || bottom <= top ||
      scale_milli < 250 || scale_milli > 4000) return 1;
  engine->words.clear();
  engine->text.clear();
  try {
    Apartment apartment;
    if (FAILED(apartment.status)) return 4;
    const auto recognizer = CreateOcr();
    if (!recognizer) return 5;
    const int width = right - left, height = bottom - top;
    const double limit = static_cast<double>(ocr::OcrEngine::MaxImageDimension());
    double scale = scale_milli / 1000.0;
    scale = std::min({scale, limit / width, limit / height});
    // Reference parity: no resampling at an effective factor of about one.
    const bool resample = std::abs(scale - 1.0) > 0.01;
    if (!resample) scale = 1.0;
    const UINT out_w = static_cast<UINT>(std::max(1L, std::lround(width * scale)));
    const UINT out_h = static_cast<UINT>(std::max(1L, std::lround(height * scale)));
    std::vector<uint8_t> crop(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
      const auto* p = engine->rgba.get() +
        (static_cast<size_t>(top + y) * engine->width + left + x) * 4;
      auto* q = crop.data() + (static_cast<size_t>(y) * width + x) * 4;
      q[0] = p[2]; q[1] = p[1]; q[2] = p[0]; q[3] = 255;
    }
    const UINT stride = out_w * 4;
    winrt::Windows::Storage::Streams::Buffer buffer(stride * out_h);
    buffer.Length(stride * out_h);
    uint8_t* pixels = buffer.data();
    if (resample) {
      ComPtr<IWICImagingFactory> factory;
      ComPtr<IWICBitmap> source;
      ComPtr<IWICBitmapScaler> scaler;
      if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
            CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.GetAddressOf()))) ||
          FAILED(factory->CreateBitmapFromMemory(width, height,
            GUID_WICPixelFormat32bppBGRA, width * 4,
            static_cast<UINT>(crop.size()), crop.data(), source.GetAddressOf())) ||
          FAILED(factory->CreateBitmapScaler(scaler.GetAddressOf())) ||
          FAILED(scaler->Initialize(source.Get(), out_w, out_h,
            WICBitmapInterpolationModeHighQualityCubic)) ||
          FAILED(scaler->CopyPixels(nullptr, stride, stride * out_h, pixels))) return 4;
    } else {
      std::memcpy(pixels, crop.data(), crop.size());
    }
    if (enhance) {
      for (size_t i = 0; i < static_cast<size_t>(out_w) * out_h * 4; i += 4) {
        const uint8_t value =
          LikelyPanelText(pixels[i + 2], pixels[i + 1], pixels[i]) ? 0 : 255;
        pixels[i] = pixels[i + 1] = pixels[i + 2] = value;
        pixels[i + 3] = 255;
      }
    }
    const auto bitmap = imaging::SoftwareBitmap::CreateCopyFromBuffer(buffer,
      imaging::BitmapPixelFormat::Bgra8, out_w, out_h,
      imaging::BitmapAlphaMode::Premultiplied);
    const auto result = recognizer.RecognizeAsync(bitmap).get();
    engine->text = winrt::to_string(result.Text());
    if (engine->text.size() > 64 * 1024) { engine->text.clear(); return 4; }
    int32_t index = 0;
    for (const auto& line : result.Lines()) {
      for (const auto& word : line.Words()) {
        if (engine->words.size() >= 4096) return 4;
        const auto rect = word.BoundingRect();
        auto text = winrt::to_string(word.Text());
        if (text.empty() || text.size() > 2048) continue;
        const auto map = [&](double v, int origin, int extent) {
          return origin + std::clamp(static_cast<int>(std::floor(v / scale)), 0, extent);
        };
        Word mapped{map(rect.X, left, width - 1), map(rect.Y, top, height - 1),
          map(rect.X + rect.Width, left, width), map(rect.Y + rect.Height, top, height),
          index, std::move(text)};
        if (mapped.right <= mapped.left) mapped.right = mapped.left + 1;
        if (mapped.bottom <= mapped.top) mapped.bottom = mapped.top + 1;
        engine->words.push_back(std::move(mapped));
      }
      ++index;
    }
    return 0;
  } catch (const winrt::hresult_error&) {
    engine->words.clear();
    engine->text.clear();
    return 3;
  } catch (...) { engine->words.clear(); engine->text.clear(); return 4; }
}
BG_API int32_t bg_ocr_width(Engine* engine) { return engine ? engine->width : 0; }
BG_API int32_t bg_ocr_height(Engine* engine) { return engine ? engine->height : 0; }
BG_API int32_t bg_ocr_count(Engine* engine) { return engine ? static_cast<int>(engine->words.size()) : 0; }
BG_API int32_t bg_ocr_word(Engine* engine, int32_t index, BgWord* result) {
  if (!engine || !result || index < 0 || static_cast<size_t>(index) >= engine->words.size()) return 1;
  const auto& word = engine->words[index];
  *result = {word.left, word.top, word.right, word.bottom, word.line, word.text.c_str()};
  return 0;
}
// Engine-joined text of the last recognition; owned by the engine.
BG_API const char* bg_ocr_text(Engine* engine) { return engine ? engine->text.c_str() : nullptr; }
BG_API uint32_t bg_ocr_rgb(Engine* engine, int32_t x, int32_t y) {
  if (!engine || x < 0 || y < 0 || x >= engine->width || y >= engine->height) return 0;
  const auto* p = engine->rgba.get() + (static_cast<size_t>(y) * engine->width + x) * 4;
  return (static_cast<uint32_t>(p[0]) << 16) | (static_cast<uint32_t>(p[1]) << 8) | p[2];
}
