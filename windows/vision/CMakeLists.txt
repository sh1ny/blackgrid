# Item vision runtime (ADR-0008): OpenCV 4.13.0 core+imgproc built from the
# pinned, verified source archive, and the owned blackgrid_vision.dll.
cmake_minimum_required(VERSION 3.20)
if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "The vision runtime requires Windows x64")
endif()
include(ExternalProject)
include("${CMAKE_CURRENT_LIST_DIR}/verify_inputs.cmake")

get_filename_component(BGV_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(BGV_LOCK_FILE "${CMAKE_CURRENT_LIST_DIR}/third_party.lock.json")
set(BGV_INPUT_CACHE "${BGV_REPO_ROOT}/.dart_tool/blackgrid_vision_inputs")
# Re-run configure, and so re-verify, whenever the pins change.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${BGV_LOCK_FILE}")
# Refuses (FATAL_ERROR) any missing or altered input before anything builds.
bgv_verify_inputs("${BGV_LOCK_FILE}" "${BGV_INPUT_CACHE}")
file(READ "${BGV_LOCK_FILE}" BGV_LOCK_JSON)

# --- OpenCV 4.13.0, static core + imgproc, static CRT -----------------------
# Release and Profile link the Release (/MT) build; Debug links a separate
# Debug (/MTd) build. Each configuration has its own install prefix and is
# built once, then reused.
string(JSON BGV_OPENCV_SHA256 GET "${BGV_LOCK_JSON}" inputs 0 sha256)
string(JSON BGV_OPENCV_ID GET "${BGV_LOCK_JSON}" inputs 0 id)
if(NOT BGV_OPENCV_ID STREQUAL "opencv-source")
  message(FATAL_ERROR "third_party.lock.json: inputs[0] must be opencv-source")
endif()
set(BGV_OPENCV_CONFIG "$<IF:$<CONFIG:Debug>,Debug,Release>")
set(BGV_OPENCV_ROOT "${CMAKE_BINARY_DIR}/opencv-install")
set(BGV_OPENCV_PREFIX "${BGV_OPENCV_ROOT}/${BGV_OPENCV_CONFIG}")
# Content-addressed source tree, extracted once and shared by every
# configuration. ExternalProject's own URL step would re-extract and rename
# over it for each configuration.
string(SUBSTRING "${BGV_OPENCV_SHA256}" 0 16 BGV_OPENCV_SHORT)
set(BGV_OPENCV_EXTRACT "${CMAKE_BINARY_DIR}/opencv/src-${BGV_OPENCV_SHORT}")

ExternalProject_Add(bgv_opencv
  PREFIX "${CMAKE_BINARY_DIR}/opencv"
  SOURCE_DIR "${BGV_OPENCV_EXTRACT}/opencv-4.13.0"
  DOWNLOAD_COMMAND
    ${CMAKE_COMMAND} "-DARCHIVE=${BGV_INPUT_OPENCV_SOURCE}"
      "-DSHA256=${BGV_OPENCV_SHA256}" "-DDEST=${BGV_OPENCV_EXTRACT}"
      -P "${CMAKE_CURRENT_LIST_DIR}/extract_source.cmake"
  UPDATE_COMMAND ""
  PATCH_COMMAND ""
  CMAKE_ARGS
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_WITH_STATIC_CRT=ON
    -DBUILD_LIST=core,imgproc
    -DBUILD_ZLIB=ON
    -DWITH_ZLIB_NG=OFF
    -DBUILD_TESTS=OFF
    -DBUILD_PERF_TESTS=OFF
    -DBUILD_EXAMPLES=OFF
    -DBUILD_DOCS=OFF
    -DBUILD_opencv_apps=OFF
    -DBUILD_JAVA=OFF
    -DBUILD_opencv_python2=OFF
    -DBUILD_opencv_python3=OFF
    -DOPENCV_PYTHON_SKIP_DETECTION=ON
    -DOPENCV_SKIP_PYTHON_LOADER=ON
    -DBUILD_opencv_python_bindings_generator=OFF
    -DBUILD_opencv_java_bindings_generator=OFF
    -DBUILD_opencv_js_bindings_generator=OFF
    -DBUILD_opencv_objc_bindings_generator=OFF
    -DBUILD_IPP_IW=OFF
    -DBUILD_ITT=OFF
    -DWITH_IPP=OFF
    -DWITH_OPENCL=OFF
    -DWITH_OPENCL_SVM=OFF
    -DWITH_OPENCLAMDFFT=OFF
    -DWITH_OPENCLAMDBLAS=OFF
    -DWITH_ADE=OFF
    -DWITH_EIGEN=OFF
    -DWITH_ITT=OFF
    -DWITH_PROTOBUF=OFF
    -DWITH_FLATBUFFERS=OFF
    -DWITH_LAPACK=OFF
    -DWITH_OPENMP=OFF
    -DWITH_TBB=OFF
    -DWITH_HPX=OFF
    -DWITH_CUDA=OFF
    -DWITH_OPENVINO=OFF
    -DWITH_VULKAN=OFF
    -DWITH_HALIDE=OFF
    -DWITH_WEBNN=OFF
    -DWITH_ONNX=OFF
    -DWITH_KLEIDICV=OFF
    -DWITH_CAROTENE=OFF
    -DWITH_FASTCV=OFF
    -DWITH_DIRECTX=OFF
    -DWITH_DIRECTML=OFF
    -DWITH_OPENGL=OFF
    -DWITH_QT=OFF
    -DWITH_WIN32UI=OFF
    -DWITH_VTK=OFF
    -DWITH_FFMPEG=OFF
    -DWITH_GSTREAMER=OFF
    -DWITH_DSHOW=OFF
    -DWITH_MSMF=OFF
    -DWITH_MSMF_DXVA=OFF
    -DWITH_OBSENSOR=OFF
    -DWITH_1394=OFF
    -DWITH_JPEG=OFF
    -DWITH_JPEGXL=OFF
    -DWITH_PNG=OFF
    -DWITH_SPNG=OFF
    -DWITH_TIFF=OFF
    -DWITH_WEBP=OFF
    -DWITH_AVIF=OFF
    -DWITH_OPENEXR=OFF
    -DWITH_OPENJPEG=OFF
    -DWITH_JASPER=OFF
    -DWITH_GDAL=OFF
    -DWITH_GDCM=OFF
    -DWITH_IMGCODEC_GIF=OFF
    -DWITH_IMGCODEC_HDR=OFF
    -DWITH_IMGCODEC_SUNRASTER=OFF
    -DWITH_IMGCODEC_PXM=OFF
    -DWITH_IMGCODEC_PFM=OFF
    -DWITH_QUIRC=OFF
    -DCV_TRACE=OFF
    -DOPENCV_GENERATE_PKGCONFIG=OFF
    -DOPENCV_LIB_INSTALL_PATH=lib
    -DOPENCV_LIB_ARCHIVE_INSTALL_PATH=lib
    -DOPENCV_3P_LIB_INSTALL_PATH=lib/3rdparty
    -DOPENCV_CONFIG_INSTALL_PATH=lib/cmake/opencv4
    -DOPENCV_INCLUDE_INSTALL_PATH=include
    -DOPENCV_LICENSES_INSTALL_PATH=licenses
    -DOPENCV_OTHER_INSTALL_PATH=etc
  BUILD_COMMAND
    ${CMAKE_COMMAND} --build <BINARY_DIR> --config ${BGV_OPENCV_CONFIG} --parallel
  INSTALL_COMMAND
    ${CMAKE_COMMAND} --install <BINARY_DIR> --config ${BGV_OPENCV_CONFIG}
      --prefix ${BGV_OPENCV_PREFIX}
)
