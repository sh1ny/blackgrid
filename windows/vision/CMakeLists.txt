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
# Source, build and install trees are all keyed by the pinned archive hash, so
# a pin change starts fresh trees instead of meeting a CMake cache or leftover
# files from the earlier source. The source tree is extracted once and shared
# by every configuration; ExternalProject's own URL step would re-extract and
# rename over it for each configuration.
string(SUBSTRING "${BGV_OPENCV_SHA256}" 0 16 BGV_OPENCV_SHORT)
set(BGV_OPENCV_EXTRACT "${CMAKE_BINARY_DIR}/opencv/src-${BGV_OPENCV_SHORT}")
set(BGV_OPENCV_ROOT "${CMAKE_BINARY_DIR}/opencv-install-${BGV_OPENCV_SHORT}")
set(BGV_OPENCV_PREFIX "${BGV_OPENCV_ROOT}/${BGV_OPENCV_CONFIG}")

ExternalProject_Add(bgv_opencv
  PREFIX "${CMAKE_BINARY_DIR}/opencv"
  SOURCE_DIR "${BGV_OPENCV_EXTRACT}/opencv-4.13.0"
  BINARY_DIR "${CMAKE_BINARY_DIR}/opencv/build-${BGV_OPENCV_SHORT}"
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
    # Serial code only: no ConcRT scheduler threads alive inside a DLL that
    # Dart unloads with DynamicLibrary.close(). Callers serialise bgv_* calls.
    -DOPENCV_DISABLE_THREAD_SUPPORT=ON
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

# --- blackgrid_vision.dll: the owned bgv_* C ABI (design D4) -----------------
# The OpenCV libraries come from the prefix of the matching configuration.
set(BGV_OPENCV_SUFFIX "$<$<CONFIG:Debug>:d>")
add_library(blackgrid_vision SHARED "vision.cpp" "vision.h")
add_dependencies(blackgrid_vision bgv_opencv)
set_target_properties(blackgrid_vision PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
  MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_compile_options(blackgrid_vision PRIVATE /W4 /WX /EHsc /permissive-)
target_compile_definitions(blackgrid_vision PRIVATE
  BLACKGRID_VISION_EXPORTS NOMINMAX WIN32_LEAN_AND_MEAN)
# SYSTEM: OpenCV's own headers are outside /W4 /WX (they trip C4864).
target_include_directories(blackgrid_vision SYSTEM PRIVATE
  "${BGV_OPENCV_PREFIX}/include")
target_link_libraries(blackgrid_vision PRIVATE
  "${BGV_OPENCV_PREFIX}/lib/opencv_imgproc4130${BGV_OPENCV_SUFFIX}.lib"
  "${BGV_OPENCV_PREFIX}/lib/opencv_core4130${BGV_OPENCV_SUFFIX}.lib"
  "${BGV_OPENCV_PREFIX}/lib/3rdparty/zlib${BGV_OPENCV_SUFFIX}.lib")

# --- Bundle install (design D3, D7) -----------------------------------------
# INSTALL_BUNDLE_LIB_DIR (exe directory) and INSTALL_BUNDLE_DATA_DIR come from
# windows/CMakeLists.txt.
function(bgv_lock_entry id out_index)
  string(JSON count LENGTH "${BGV_LOCK_JSON}" inputs)
  math(EXPR last "${count} - 1")
  foreach(index RANGE ${last})
    string(JSON entry_id GET "${BGV_LOCK_JSON}" inputs ${index} id)
    if(entry_id STREQUAL id)
      set(${out_index} ${index} PARENT_SCOPE)
      return()
    endif()
  endforeach()
  message(FATAL_ERROR "third_party.lock.json has no '${id}' input")
endfunction()

# The ABI the manifest records is the one the DLL is compiled with.
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/vision.h" BGV_ABI_LINE
  REGEX "^#define BGV_ABI_VERSION [0-9]+$")
string(REGEX REPLACE "^#define BGV_ABI_VERSION " "" BGV_ABI_VERSION "${BGV_ABI_LINE}")
if(NOT BGV_ABI_VERSION MATCHES "^[0-9]+$")
  message(FATAL_ERROR "vision.h must define BGV_ABI_VERSION as one integer")
endif()
bgv_lock_entry(tesseract-nupkg BGV_NUPKG_INDEX)
string(JSON BGV_ENGINE_VERSION GET "${BGV_LOCK_JSON}"
  inputs ${BGV_NUPKG_INDEX} engineVersion)

# Third-party files: <lock id> <input variable>. Each is installed at its
# lock bundlePath, and its installed bytes are re-checked against the lock
# below, so a cache altered after configure cannot enter the bundle.
set(BGV_THIRD_PARTY
  tesseract-dll BGV_INPUT_TESSERACT_DLL
  leptonica-dll BGV_INPUT_LEPTONICA_DLL
  eng-traineddata BGV_INPUT_ENG_TRAINEDDATA)
set(BGV_MANIFEST_FILES "blackgrid_vision.dll")
set(BGV_PIN_CHECKS "")
list(LENGTH BGV_THIRD_PARTY BGV_THIRD_PARTY_LENGTH)
math(EXPR BGV_THIRD_PARTY_LAST "${BGV_THIRD_PARTY_LENGTH} - 1")
foreach(index RANGE 0 ${BGV_THIRD_PARTY_LAST} 2)
  math(EXPR value_index "${index} + 1")
  list(GET BGV_THIRD_PARTY ${index} id)
  list(GET BGV_THIRD_PARTY ${value_index} input_var)
  bgv_lock_entry(${id} lock_index)
  string(JSON bundle_path GET "${BGV_LOCK_JSON}" inputs ${lock_index} bundlePath)
  string(JSON pinned GET "${BGV_LOCK_JSON}" inputs ${lock_index} sha256)
  string(TOLOWER "${pinned}" pinned)
  get_filename_component(bundle_dir "${bundle_path}" DIRECTORY)
  get_filename_component(bundle_name "${bundle_path}" NAME)
  get_filename_component(input_name "${${input_var}}" NAME)
  if(NOT input_name STREQUAL bundle_name)
    message(FATAL_ERROR "Vision input '${id}' (${input_name}) must install as ${bundle_path}")
  endif()
  install(FILES "${${input_var}}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/${bundle_dir}" COMPONENT Runtime)
  list(APPEND BGV_MANIFEST_FILES "${bundle_path}")
  list(APPEND BGV_PIN_CHECKS "${bundle_path}|${pinned}")
endforeach()

install(FILES "$<TARGET_FILE:blackgrid_vision>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

# Self-check sample (task 5.1 output), read by --vision-self-check.
set(BGV_SELF_CHECK_FILES title.gray title.json)
foreach(name ${BGV_SELF_CHECK_FILES})
  install(FILES "${BGV_REPO_ROOT}/assets/vision/self_check/${name}"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/vision/self_check" COMPONENT Runtime)
  list(APPEND BGV_MANIFEST_FILES "data/vision/self_check/${name}")
endforeach()

# Inspection marker template and its metadata (add-inspection-recognition-
# pipeline task 3.6), loaded by loadMarkerTemplate and bound by the manifest.
set(BGV_MARKER_FILES inspection_marker.gray inspection_marker.json)
foreach(name ${BGV_MARKER_FILES})
  install(FILES "${BGV_REPO_ROOT}/assets/vision/marker/${name}"
    DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/vision/marker" COMPONENT Runtime)
  list(APPEND BGV_MANIFEST_FILES "data/vision/marker/${name}")
endforeach()

# App-local Visual C++ runtime for the Flutter runner and tesseract50.dll
# (D7), filtered to the committed name list. Minimum versions are checked by
# tool/vision/check_bundle.dart.
set(BGV_VC_RUNTIME_NAMES msvcp140.dll vcruntime140.dll vcruntime140_1.dll)
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
set(CMAKE_INSTALL_UCRT_LIBRARIES FALSE)
set(CMAKE_INSTALL_DEBUG_LIBRARIES FALSE)
include(InstallRequiredSystemLibraries)
foreach(name ${BGV_VC_RUNTIME_NAMES})
  set(found "")
  foreach(lib ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS})
    get_filename_component(lib_name "${lib}" NAME)
    string(TOLOWER "${lib_name}" lib_name)
    if(lib_name STREQUAL name)
      set(found "${lib}")
    endif()
  endforeach()
  if(NOT found)
    message(FATAL_ERROR
      "InstallRequiredSystemLibraries did not find ${name} "
      "(found: ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS})")
  endif()
  install(FILES "${found}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
  list(APPEND BGV_MANIFEST_FILES "${name}")
endforeach()

# Last: re-check third-party pins on the installed bytes, then bind every
# vision file into data/vision/runtime.manifest.json (write_manifest.cmake).
get_filename_component(BGV_LOCK_DIR "${BGV_LOCK_FILE}" DIRECTORY)
install(CODE "
  set(BGV_BUNDLE \"${INSTALL_BUNDLE_LIB_DIR}\")
  set(BGV_PIN_CHECKS \"${BGV_PIN_CHECKS}\")
  set(BGV_MANIFEST_FILES \"${BGV_MANIFEST_FILES}\")
  set(BGV_ABI_VERSION \"${BGV_ABI_VERSION}\")
  set(BGV_ENGINE_VERSION \"${BGV_ENGINE_VERSION}\")
  set(BGV_PROTECTED_DIRS \"${BGV_INPUT_CACHE};${BGV_LOCK_DIR}\")
  include(\"${CMAKE_CURRENT_LIST_DIR}/write_manifest.cmake\")
  " COMPONENT Runtime)
