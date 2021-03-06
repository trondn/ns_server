CMAKE_MINIMUM_REQUIRED (VERSION 2.8)

PROJECT (ns_server)
LIST (APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake_modules")
INCLUDE (FindCouchbaseErlang)
INCLUDE (FindCouchbaseGo)

# Global project variables

# Installation subdir
SET (INST_LIBDIR "lib/ns_server/erlang/lib")

# Cache "git describe" output
EXECUTE_PROCESS(COMMAND git describe
  WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
  OUTPUT_VARIABLE _git_describe
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE)
SET (NS_SERVER_VERSION "${_git_describe}" CACHE STRING "Output of git describe" FORCE)
MARK_AS_ADVANCED (NS_SERVER_VERSION)

# Create rebar.config
SET (COUCHDB_SRC "${PROJECT_SOURCE_DIR}/../couchdb" CACHE PATH "Path to couchdb source")
IF (NOT EXISTS "${COUCHDB_SRC}/src/couchdb/couch_db.hrl")
  MESSAGE (FATAL_ERROR "Could not find couch_db.hrl; please re-run CMake with "
    "-DCOUCHDB_SRC=<path/to/couchdb source>")
ENDIF (NOT EXISTS "${COUCHDB_SRC}/src/couchdb/couch_db.hrl")
CONFIGURE_FILE ("${PROJECT_SOURCE_DIR}/rebar.config.in"
  "${PROJECT_SOURCE_DIR}/rebar.config" @ONLY)

# Other generated files
SET (all_img_js "${PROJECT_SOURCE_DIR}/priv/public/js/all-images.js")
ADD_CUSTOM_COMMAND (OUTPUT "${all_img_js}"
  COMMAND "${CMAKE_COMMAND}" -D "pubdir=${PROJECT_SOURCE_DIR}/priv/public"
  -D "outfile=${all_img_js}"
  -P "${PROJECT_SOURCE_DIR}/cmake_modules/build-all-images.cmake")
ADD_CUSTOM_TARGET (all_images ALL DEPENDS "${all_img_js}")

CONFIGURE_FILE ("${PROJECT_SOURCE_DIR}/src/ns_server.app.src.in"
  "${PROJECT_SOURCE_DIR}/src/ns_server.app.src" @ONLY)

FILE (WRITE "${PROJECT_BINARY_DIR}/cluster_run.configuration"
  "prefix=\"${CMAKE_INSTALL_PREFIX}\"\n")

# Various cleaning targets
ADD_CUSTOM_TARGET (ns_realclean
  COMMAND "${CMAKE_COMMAND}" --build "${PROJECT_BINARY_DIR}" --target clean
  COMMAND "${CMAKE_COMMAND}" -E remove -f cov.html erl_crash.dump deps/vbmap/vbmap
  COMMAND "${CMAKE_COMMAND}" -E remove_directory test/log
  COMMAND "${CMAKE_COMMAND}" -E remove_directory ebin
  COMMAND "${CMAKE_COMMAND}" -E remove_directory docs
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
  VERBATIM)
ADD_DEPENDENCIES (realclean ns_realclean)

ADD_CUSTOM_TARGET (ns_dataclean
  COMMAND "${CMAKE_COMMAND}" -E remove_directory data
  COMMAND "${CMAKE_COMMAND}" -E remove_directory coverage
  COMMAND "${CMAKE_COMMAND}" -E remove_directory couch
  COMMAND "${CMAKE_COMMAND}" -E remove_directory logs
  COMMAND "${CMAKE_COMMAND}" -E remove_directory tmp
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
  VERBATIM)

ADD_CUSTOM_TARGET (ns_distclean)
ADD_DEPENDENCIES (ns_distclean realclean ns_dataclean)


# Source compilation (must be after adding "realclean" target so rebar will
# join the realclean party)
ADD_SUBDIRECTORY (deps)
Rebar (TARGET ns_server NOCLEAN
  DEPENDS ale erlwsh mlockall ns_babysitter ns_ssl_proxy)


# Test invocation
ADD_CUSTOM_TARGET (ns_test
  "${CMAKE_COMMAND}" -D "ERL_EXECUTABLE=${ERL_EXECUTABLE}"
  -D "COUCHDB_SRC=${COUCHDB_SRC}"
  -P "${PROJECT_SOURCE_DIR}/cmake_modules/do-test.cmake"
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
  VERBATIM)
ADD_DEPENDENCIES (ns_test ns_server)

# Docs
ADD_CUSTOM_TARGET (ns_docs COMMAND priv/erldocs ./docs/erldocs
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}" VERBATIM)

# Dialyzer targets

# Find OTP version
EXECUTE_PROCESS (COMMAND "${ERL_EXECUTABLE}" -noshell -eval
  "io:format(\"~s~n\", [erlang:system_info(otp_release)]), erlang:halt()."
  OUTPUT_VARIABLE OTP_RELEASE)

# Get COUCHBASE_PLT from environment, if specified
IF (DEFINED ENV{COUCHBASE_PLT})
  SET (_couchbase_plt "$ENV{COUCHBASE_PLT}")
  SET (_force_plt FORCE)
ELSE (DEFINED ENV{COUCHBASE_PLT})
  SET (_couchbase_plt "${PROJECT_SOURCE_DIR}/couchbase.plt")
ENDIF (DEFINED ENV{COUCHBASE_PLT})
GET_FILENAME_COMPONENT (_couchbase_plt "${_couchbase_plt}" REALPATH)
SET (COUCHBASE_PLT "${_couchbase_plt}" CACHE FILEPATH
  "Full path to couchbase.plt for dialyzer targets" ${_force_plt})
MESSAGE (STATUS "COUCHBASE_PLT set to ${COUCHBASE_PLT}")

GET_FILENAME_COMPONENT (_real_couchdb_src "${COUCHDB_SRC}" REALPATH)
ADD_CUSTOM_COMMAND (OUTPUT "${COUCHBASE_PLT}"
  COMMAND dialyzer --output_plt "${COUCHBASE_PLT}" --build_plt
    --apps compiler crypto erts inets kernel os_mon sasl ssl stdlib xmerl
    ${COUCHDB_SRC}/src/mochiweb
    ${COUCHDB_SRC}/src/snappy ${COUCHDB_SRC}/src/etap
    # MISSING?  ${_real_couchdb_src}/src/ibrowse
    ${_real_couchdb_src}/src/lhttpc
    ${COUCHDB_SRC}/src/erlang-oauth deps/erlwsh/ebin deps/gen_smtp/ebin
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}")

SET (dialyzer_args -Wno_return -Wno_improper_lists)
IF (OTP_RELEASE MATCHES "^R1[5-9]B.*$$")
  LIST (APPEND dialyzer_args -Wno_undefined_callbacks)
ENDIF (OTP_RELEASE MATCHES "^R1[5-9]B.*$$")
ADD_CUSTOM_TARGET (ns_dialyzer DEPENDS "${COUCHBASE_PLT}"
  COMMAND "${CMAKE_COMMAND}" -D "COUCHDB_SRC=${COUCHDB_SRC}"
  -D "DIALYZER_FLAGS=${dialyzer_args}"
  -D "COUCHBASE_PLT=${COUCHBASE_PLT}"
  -P "${PROJECT_SOURCE_DIR}/cmake_modules/do-dialyzer.cmake"
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}" VERBATIM)
ADD_DEPENDENCIES (ns_dialyzer ns_server)

SET (obsessive_args -Wunmatched_returns -Werror_handling -Wrace_conditions
  -Wbehaviours -Wunderspecs)
ADD_CUSTOM_TARGET (ns_dialyzer_obsessive DEPENDS "${COUCHBASE_PLT}"
  COMMAND "${CMAKE_COMMAND}" -D "COUCHDB_SRC=${COUCHDB_SRC}"
  -D "DIALYZER_FLAGS=${obsessive_args}"
  -D "COUCHBASE_PLT=${COUCHBASE_PLT}"
  -P "${PROJECT_SOURCE_DIR}/cmake_modules/do-dialyzer.cmake"
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}" VERBATIM)
ADD_DEPENDENCIES (ns_dialyzer_obsessive ns_server)

#
# Install
#
INSTALL (DIRECTORY ebin DESTINATION "${INST_LIBDIR}/ns_server")
INSTALL (DIRECTORY priv/public DESTINATION "${INST_LIBDIR}/ns_server/priv")
INSTALL (FILES priv/i386-linux-godu priv/i386-win32-godu.exe
  DESTINATION "${INST_LIBDIR}/ns_server/priv")

INSTALL (PROGRAMS cbbrowse_logs cbcollect_info cbreset_password DESTINATION bin)
INSTALL (PROGRAMS scripts/cbdump-config scripts/dump-guts DESTINATION bin)

# Configure custom copies of scripts for installation
SET (PREFIX "${CMAKE_INSTALL_PREFIX}")
SET (_instdir "${PROJECT_BINARY_DIR}/instfiles")
FILE (REMOVE_RECURSE "${_instdir}")
CONFIGURE_FILE (couchbase-server.sh.in "${_instdir}/couchbase-server" @ONLY)
INSTALL (PROGRAMS "${_instdir}/couchbase-server" DESTINATION bin)

SET (_etcdir "${_instdir}/etc")
FILE (MAKE_DIRECTORY "${_etcdir}")
CONFIGURE_FILE (etc/static_config.in "${_etcdir}/couchbase/static_config" @ONLY)
FILE (WRITE "${_etcdir}/couchbase/config" "")    # create empty file
SET (_cdbetcdir "${_etcdir}/couchdb/default.d")
FILE (MAKE_DIRECTORY "${_cdbetcdir}")
CONFIGURE_FILE (etc/geocouch.ini.in "${_cdbetcdir}/geocouch.ini" COPY_ONLY)
SET (COUCHBASE_DB_DIR "${CMAKE_INSTALL_PREFIX}/var/lib/couchbase/data")
CONFIGURE_FILE (etc/capi.ini.in "${_cdbetcdir}/capi.ini" @ONLY)
INSTALL (DIRECTORY "${_etcdir}/" DESTINATION etc)

# Empty directory to be "installed" multiple times with varying permissions
FILE (MAKE_DIRECTORY "${_instdir}/var")
INSTALL (DIRECTORY "${_instdir}/var/" DESTINATION var/lib)
INSTALL (DIRECTORY "${_instdir}/var/" DESTINATION var/lib/couchbase
  DIRECTORY_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
  GROUP_READ GROUP_WRITE GROUP_EXECUTE)
INSTALL (DIRECTORY "${_instdir}/var/" DESTINATION var/lib/couchbase/logs
  DIRECTORY_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
  GROUP_READ GROUP_WRITE GROUP_EXECUTE)





