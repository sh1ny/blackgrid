# Verifies every third-party vision input in the committed lock against the
# fetch cache (design D8). Usable two ways:
#   include(verify_inputs.cmake) then bgv_verify_inputs(<lock> <cache>)
#     sets BGV_INPUT_<ID> (id upper-cased, '-' -> '_') to each verified path.
#   cmake -DBGV_LOCK_FILE=<lock> -DBGV_INPUT_CACHE=<cache> -P verify_inputs.cmake
# Any missing or altered input is a FATAL_ERROR naming the input.

function(bgv_verify_inputs lock_file cache_dir)
  if(NOT EXISTS "${lock_file}")
    message(FATAL_ERROR "Vision input lock not found: ${lock_file}")
  endif()
  file(READ "${lock_file}" lock_json)
  string(JSON format GET "${lock_json}" format)
  if(NOT format EQUAL 1)
    message(FATAL_ERROR "Unsupported vision input lock format ${format} in ${lock_file}")
  endif()
  string(JSON count LENGTH "${lock_json}" inputs)
  if(count EQUAL 0)
    message(FATAL_ERROR "Vision input lock ${lock_file} lists no inputs")
  endif()
  math(EXPR last "${count} - 1")
  foreach(index RANGE ${last})
    string(JSON id GET "${lock_json}" inputs ${index} id)
    string(JSON name GET "${lock_json}" inputs ${index} name)
    string(JSON expected GET "${lock_json}" inputs ${index} sha256)
    string(TOLOWER "${expected}" expected)
    set(path "${cache_dir}/${expected}/${name}")
    if(NOT EXISTS "${path}")
      message(FATAL_ERROR
        "Vision input '${id}' is missing from the verified cache (${path}). "
        "Run `mise run vision:fetch`, then build again.")
    endif()
    file(SHA256 "${path}" actual)
    if(NOT actual STREQUAL expected)
      message(FATAL_ERROR
        "Vision input '${id}' does not match its pin: expected SHA-256 "
        "${expected}, cached file ${path} has ${actual}. Delete it and run "
        "`mise run vision:fetch`.")
    endif()
    string(TOUPPER "${id}" var)
    string(REPLACE "-" "_" var "${var}")
    set(BGV_INPUT_${var} "${path}" PARENT_SCOPE)
  endforeach()
endfunction()

if(CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
  if(NOT DEFINED BGV_LOCK_FILE OR NOT DEFINED BGV_INPUT_CACHE)
    message(FATAL_ERROR "Usage: cmake -DBGV_LOCK_FILE=<lock> -DBGV_INPUT_CACHE=<cache> -P verify_inputs.cmake")
  endif()
  bgv_verify_inputs("${BGV_LOCK_FILE}" "${BGV_INPUT_CACHE}")
  message(STATUS "All vision inputs verified against ${BGV_LOCK_FILE}")
endif()
