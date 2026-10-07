# Install step for the vision runtime binding (design D3), included from an
# install(CODE) block in CMakeLists.txt with:
#   BGV_BUNDLE          exe directory of the installed bundle
#   BGV_PIN_CHECKS      list of "<bundle path>|<lock sha256>" for third-party files
#   BGV_MANIFEST_FILES  list of bundle paths, relative to BGV_BUNDLE
#   BGV_ABI_VERSION     vision ABI the DLL was compiled with
#   BGV_ENGINE_VERSION  Tesseract engine version from the lock
#   BGV_PROTECTED_DIRS  input directories the manifest must not land in
# Third-party files are re-checked against the lock on their installed bytes,
# so a cache altered after configure cannot enter the bundle. Then every
# vision file is hashed into data/vision/runtime.manifest.json, written to a
# temporary file and renamed into place.
foreach(var BGV_BUNDLE BGV_MANIFEST_FILES BGV_ABI_VERSION BGV_ENGINE_VERSION)
  if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
    message(FATAL_ERROR "write_manifest.cmake: ${var} is required")
  endif()
endforeach()

foreach(check IN LISTS BGV_PIN_CHECKS)
  string(REPLACE "|" ";" check "${check}")
  list(GET check 0 path)
  list(GET check 1 pinned)
  file(SHA256 "${BGV_BUNDLE}/${path}" actual)
  if(NOT actual STREQUAL pinned)
    message(FATAL_ERROR
      "Installed ${path} does not match its lock pin: expected SHA-256 "
      "${pinned}, got ${actual}. Run `mise run vision:fetch` and rebuild.")
  endif()
endforeach()

set(json "{}")
string(JSON json SET "${json}" format 1)
string(JSON json SET "${json}" abi ${BGV_ABI_VERSION})
string(JSON json SET "${json}" engineVersion "\"${BGV_ENGINE_VERSION}\"")
string(JSON json SET "${json}" files "[]")
set(index 0)
foreach(path IN LISTS BGV_MANIFEST_FILES)
  set(file "${BGV_BUNDLE}/${path}")
  if(NOT EXISTS "${file}")
    message(FATAL_ERROR "Vision file ${path} was not installed")
  endif()
  file(SHA256 "${file}" hash)
  file(SIZE "${file}" size)
  string(JSON json SET "${json}" files ${index}
    "{\"path\": \"${path}\", \"sha256\": \"${hash}\", \"size\": ${size}}")
  math(EXPR index "${index} + 1")
endforeach()

set(manifest "${BGV_BUNDLE}/data/vision/runtime.manifest.json")
# The manifest and its temp file must not replace a link or land in the
# verified input cache or beside the lock, whatever links the paths go through.
foreach(target "${manifest}" "${manifest}.tmp")
  if(IS_SYMLINK "${target}")
    message(FATAL_ERROR "Refusing to write the manifest through link ${target}")
  endif()
endforeach()
file(REAL_PATH "${BGV_BUNDLE}/data/vision" manifest_dir)
string(TOLOWER "${manifest_dir}/" manifest_dir_key)
foreach(dir IN LISTS BGV_PROTECTED_DIRS)
  if(NOT EXISTS "${dir}")
    continue()
  endif()
  file(REAL_PATH "${dir}" protected)
  string(TOLOWER "${protected}/" protected_key)
  string(FIND "${manifest_dir_key}" "${protected_key}" at)
  if(at EQUAL 0)
    message(FATAL_ERROR
      "Refusing to write the manifest into ${manifest_dir}: it resolves inside "
      "the input directory ${protected}. Install the bundle elsewhere.")
  endif()
endforeach()
file(WRITE "${manifest}.tmp" "${json}\n")
file(RENAME "${manifest}.tmp" "${manifest}")
