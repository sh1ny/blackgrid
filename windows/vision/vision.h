// Blackgrid item vision primitives: a versioned C ABI over caller-owned
// 8-bit image buffers (design D4). No function allocates memory that outlives
// the call, and no C++ exception crosses the boundary. OpenCV is built without
// thread support, so callers must serialise calls (one owning isolate).
#pragma once

#include <stdint.h>

#ifdef BLACKGRID_VISION_EXPORTS
#define BGV_API extern "C" __declspec(dllexport)
#else
#define BGV_API extern "C" __declspec(dllimport)
#endif

// Bumped whenever a signature, status code or semantic changes.
#define BGV_ABI_VERSION 1

// Status codes. Non-negative values are successful outcomes.
#define BGV_OK 0
#define BGV_NOT_FOUND 1          // bgv_find_in_range_row: no pixel in range
#define BGV_ERR_ARGUMENT (-1)    // null pointer or out-of-range scalar
#define BGV_ERR_IMAGE (-2)       // cap violated, uniform template, bad score
#define BGV_ERR_OPENCV (-3)      // cv::Exception caught at the boundary
#define BGV_ERR_NO_MEMORY (-4)   // std::bad_alloc caught at the boundary
#define BGV_ERR_INTERNAL (-5)    // any other exception caught at the boundary

// Image caps, checked natively as well as in Dart.
#define BGV_MAX_SIDE 8192
#define BGV_MAX_PIXELS (24 * 1024 * 1024)

// bgv_resize interpolation.
#define BGV_INTER_CUBIC 0
#define BGV_INTER_AREA 1

BGV_API int32_t bgv_abi(void);

// src: channels 1, 3 or 4. rgb_order 0 = BGR(A), 1 = RGB(A); ignored for 1
// channel. dst: 1 channel, w x h, dst_stride >= w.
BGV_API int32_t bgv_to_gray(const uint8_t* src, int32_t w, int32_t h,
                            int32_t stride, int32_t channels, int32_t rgb_order,
                            uint8_t* dst, int32_t dst_stride);

// dst has the same channel count as src, dw x dh, dst_stride >= dw*channels.
BGV_API int32_t bgv_resize(const uint8_t* src, int32_t w, int32_t h,
                           int32_t stride, int32_t channels, uint8_t* dst,
                           int32_t dw, int32_t dh, int32_t dst_stride,
                           int32_t interp);

// 1-channel src and dst: dst = src > thresh ? 0 : maxval.
BGV_API int32_t bgv_threshold_binary_inv(const uint8_t* src, int32_t w,
                                         int32_t h, int32_t stride,
                                         int32_t thresh, int32_t maxval,
                                         uint8_t* dst, int32_t dst_stride);

// 1-channel image and template; TM_CCOEFF_NORMED best (maximum) score and
// its top-left location. The template must fit inside the image. A uniform
// (zero-variance) template or a non-finite best score is BGV_ERR_IMAGE.
BGV_API int32_t bgv_match_template_best(const uint8_t* img, int32_t iw,
                                        int32_t ih, int32_t istride,
                                        const uint8_t* tpl, int32_t tw,
                                        int32_t th, int32_t tstride,
                                        double* out_score, int32_t* out_x,
                                        int32_t* out_y);

// Scans row `row` from x = start_x rightwards for the first pixel whose
// first three channels c satisfy lo[c] <= p[c] <= hi[c] (inclusive, in the
// buffer's channel order). channels 3 or 4. Returns BGV_OK with *out_x set,
// or BGV_NOT_FOUND with *out_x = -1.
BGV_API int32_t bgv_find_in_range_row(const uint8_t* src, int32_t w,
                                      int32_t h, int32_t stride,
                                      int32_t channels, int32_t row,
                                      int32_t start_x, const uint8_t* lo,
                                      const uint8_t* hi, int32_t* out_x);
