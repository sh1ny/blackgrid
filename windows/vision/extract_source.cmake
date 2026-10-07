# ExternalProject download step for a pinned source archive:
#   cmake -DARCHIVE=<zip> -DSHA256=<lock value> -DDEST=<dir> -P extract_source.cmake
# Re-checks the archive against its lock SHA-256 (the URL_HASH equivalent),
# then extracts it once into DEST. Multi-config builds run this step once per
# configuration; a completed extraction of the same hash is reused, so the
# source tree is never replaced under an earlier configuration's build.
foreach(var ARCHIVE SHA256 DEST)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "extract_source.cmake: -D${var}= is required")
  endif()
endforeach()
string(TOLOWER "${SHA256}" SHA256)
set(stamp "${DEST}/.bgv-extracted-sha256")
if(EXISTS "${stamp}")
  file(READ "${stamp}" extracted)
  if(extracted STREQUAL SHA256)
    return()
  endif()
endif()
file(SHA256 "${ARCHIVE}" actual)
if(NOT actual STREQUAL SHA256)
  message(FATAL_ERROR
    "Source archive ${ARCHIVE} does not match its pin: expected SHA-256 "
    "${SHA256}, got ${actual}. Run `mise run vision:fetch`.")
endif()
file(REMOVE_RECURSE "${DEST}")
file(MAKE_DIRECTORY "${DEST}")
file(ARCHIVE_EXTRACT INPUT "${ARCHIVE}" DESTINATION "${DEST}")
file(WRITE "${stamp}" "${SHA256}")
