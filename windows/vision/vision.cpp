// Blackgrid item vision primitives over OpenCV core + imgproc (design D4).
// Every buffer is caller-owned and wrapped in a cv::Mat header without a copy;
// outputs are written in place. Caps are re-checked here even though the Dart
// wrapper checks them first, and every exception stops at the boundary.
#include "vision.h"

#include <cmath>
#include <cstdint>
#include <exception>
#include <new>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

bool ValidImage(const uint8_t* data, int32_t w, int32_t h, int32_t stride,
                int32_t channels) {
  if (data == nullptr) return false;
  if (channels != 1 && channels != 3 && channels != 4) return false;
  if (w < 1 || h < 1 || w > BGV_MAX_SIDE || h > BGV_MAX_SIDE) return false;
  if (static_cast<int64_t>(w) * h > BGV_MAX_PIXELS) return false;
  return static_cast<int64_t>(stride) >= static_cast<int64_t>(w) * channels;
}

cv::Mat Wrap(const uint8_t* data, int32_t w, int32_t h, int32_t stride,
             int32_t channels) {
  // OpenCV never writes through an input header; the cast only satisfies
  // the cv::Mat constructor.
  return cv::Mat(h, w, CV_8UC(channels), const_cast<uint8_t*>(data),
                 static_cast<size_t>(stride));
}

// Runs `body` with every C++ exception mapped to a status code.
template <typename Body>
int32_t Guard(Body&& body) noexcept {
  try {
    return body();
  } catch (const cv::Exception&) {
    return BGV_ERR_OPENCV;
  } catch (const std::bad_alloc&) {
    return BGV_ERR_NO_MEMORY;
  } catch (...) {
    return BGV_ERR_INTERNAL;
  }
}

// An OpenCV call writing into `dst` must keep the caller's buffer. A
// reallocation would mean a header mismatch and output lost in a temporary.
int32_t CheckInPlace(const cv::Mat& dst, const uint8_t* expected) {
  return dst.data == expected ? BGV_OK : BGV_ERR_INTERNAL;
}

}  // namespace

BGV_API int32_t bgv_abi(void) { return BGV_ABI_VERSION; }

BGV_API int32_t bgv_to_gray(const uint8_t* src, int32_t w, int32_t h,
                            int32_t stride, int32_t channels, int32_t rgb_order,
                            uint8_t* dst, int32_t dst_stride) {
  if (src == nullptr || dst == nullptr) return BGV_ERR_ARGUMENT;
  if (rgb_order != 0 && rgb_order != 1) return BGV_ERR_ARGUMENT;
  if (!ValidImage(src, w, h, stride, channels) ||
      !ValidImage(dst, w, h, dst_stride, 1)) {
    return BGV_ERR_IMAGE;
  }
  return Guard([&] {
    const cv::Mat in = Wrap(src, w, h, stride, channels);
    cv::Mat out(h, w, CV_8UC1, dst, static_cast<size_t>(dst_stride));
    if (channels == 1) {
      in.copyTo(out);
    } else {
      int code;
      if (channels == 3) {
        code = rgb_order == 1 ? cv::COLOR_RGB2GRAY : cv::COLOR_BGR2GRAY;
      } else {
        code = rgb_order == 1 ? cv::COLOR_RGBA2GRAY : cv::COLOR_BGRA2GRAY;
      }
      cv::cvtColor(in, out, code);
    }
    return CheckInPlace(out, dst);
  });
}

BGV_API int32_t bgv_resize(const uint8_t* src, int32_t w, int32_t h,
                           int32_t stride, int32_t channels, uint8_t* dst,
                           int32_t dw, int32_t dh, int32_t dst_stride,
                           int32_t interp) {
  if (src == nullptr || dst == nullptr) return BGV_ERR_ARGUMENT;
  int flag;
  if (interp == BGV_INTER_CUBIC) {
    flag = cv::INTER_CUBIC;
  } else if (interp == BGV_INTER_AREA) {
    flag = cv::INTER_AREA;
  } else {
    return BGV_ERR_ARGUMENT;
  }
  if (!ValidImage(src, w, h, stride, channels) ||
      !ValidImage(dst, dw, dh, dst_stride, channels)) {
    return BGV_ERR_IMAGE;
  }
  return Guard([&] {
    const cv::Mat in = Wrap(src, w, h, stride, channels);
    cv::Mat out(dh, dw, CV_8UC(channels), dst, static_cast<size_t>(dst_stride));
    cv::resize(in, out, cv::Size(dw, dh), 0, 0, flag);
    return CheckInPlace(out, dst);
  });
}

BGV_API int32_t bgv_threshold_binary_inv(const uint8_t* src, int32_t w,
                                         int32_t h, int32_t stride,
                                         int32_t thresh, int32_t maxval,
                                         uint8_t* dst, int32_t dst_stride) {
  if (src == nullptr || dst == nullptr) return BGV_ERR_ARGUMENT;
  if (thresh < 0 || thresh > 255 || maxval < 0 || maxval > 255) {
    return BGV_ERR_ARGUMENT;
  }
  if (!ValidImage(src, w, h, stride, 1) ||
      !ValidImage(dst, w, h, dst_stride, 1)) {
    return BGV_ERR_IMAGE;
  }
  return Guard([&] {
    const cv::Mat in = Wrap(src, w, h, stride, 1);
    cv::Mat out(h, w, CV_8UC1, dst, static_cast<size_t>(dst_stride));
    cv::threshold(in, out, thresh, maxval, cv::THRESH_BINARY_INV);
    return CheckInPlace(out, dst);
  });
}

BGV_API int32_t bgv_match_template_best(const uint8_t* img, int32_t iw,
                                        int32_t ih, int32_t istride,
                                        const uint8_t* tpl, int32_t tw,
                                        int32_t th, int32_t tstride,
                                        double* out_score, int32_t* out_x,
                                        int32_t* out_y) {
  if (img == nullptr || tpl == nullptr || out_score == nullptr ||
      out_x == nullptr || out_y == nullptr) {
    return BGV_ERR_ARGUMENT;
  }
  if (!ValidImage(img, iw, ih, istride, 1) ||
      !ValidImage(tpl, tw, th, tstride, 1)) {
    return BGV_ERR_IMAGE;
  }
  if (tw > iw || th > ih) return BGV_ERR_IMAGE;
  return Guard([&] {
    const cv::Mat image = Wrap(img, iw, ih, istride, 1);
    const cv::Mat templ = Wrap(tpl, tw, th, tstride, 1);
    // A uniform template has no defined normalised correlation; OpenCV
    // special-cases it to finite scores that would read as a match.
    cv::Scalar mean;
    cv::Scalar stddev;
    cv::meanStdDev(templ, mean, stddev);
    if (stddev[0] == 0.0) return BGV_ERR_IMAGE;
    cv::Mat result;
    cv::matchTemplate(image, templ, result, cv::TM_CCOEFF_NORMED);
    double max_score = 0;
    cv::Point max_loc;
    cv::minMaxLoc(result, nullptr, &max_score, nullptr, &max_loc);
    // A flat template or image region has no defined correlation.
    if (!std::isfinite(max_score)) return BGV_ERR_IMAGE;
    *out_score = max_score;
    *out_x = max_loc.x;
    *out_y = max_loc.y;
    return BGV_OK;
  });
}

BGV_API int32_t bgv_find_in_range_row(const uint8_t* src, int32_t w,
                                      int32_t h, int32_t stride,
                                      int32_t channels, int32_t row,
                                      int32_t start_x, const uint8_t* lo,
                                      const uint8_t* hi, int32_t* out_x) {
  if (src == nullptr || lo == nullptr || hi == nullptr || out_x == nullptr) {
    return BGV_ERR_ARGUMENT;
  }
  if (channels != 3 && channels != 4) return BGV_ERR_IMAGE;
  if (!ValidImage(src, w, h, stride, channels)) return BGV_ERR_IMAGE;
  if (row < 0 || row >= h || start_x < 0 || start_x >= w) {
    return BGV_ERR_ARGUMENT;
  }
  // A plain scan: one row needs no OpenCV call and cannot throw.
  const uint8_t* p = src + static_cast<int64_t>(row) * stride +
                     static_cast<int64_t>(start_x) * channels;
  for (int32_t x = start_x; x < w; ++x, p += channels) {
    if (lo[0] <= p[0] && p[0] <= hi[0] && lo[1] <= p[1] && p[1] <= hi[1] &&
        lo[2] <= p[2] && p[2] <= hi[2]) {
      *out_x = x;
      return BGV_OK;
    }
  }
  *out_x = -1;
  return BGV_NOT_FOUND;
}
