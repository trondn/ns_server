# Compute list of .beam files
FILE (GLOB beamfiles RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" ebin/*.beam)
STRING (REGEX REPLACE "ebin/(couch_log|couch_api_wrap(_httpc)?).beam\;?" "" beamfiles "${beamfiles}")

GET_FILENAME_COMPONENT (_real_couchdb_src "${COUCHDB_SRC}" REALPATH)

# If you update the dialyzer command, please also update this echo
# command so it displays what is invoked. Yes, this is annoying.
EXECUTE_PROCESS (COMMAND "${CMAKE_COMMAND}" -E echo
  dialyzer --plt "${COUCHBASE_PLT}" ${DIALYZER_FLAGS}
  --apps ${beamfiles}
  deps/ale/ebin
  ${COUCHDB_SRC}/src/couchdb ${COUCHDB_SRC}/src/couch_set_view ${COUCHDB_SRC}/src/couch_view_parser
  ${COUCHDB_SRC}/src/couch_index_merger/ebin
  ${_real_couchdb_src}/src/mapreduce
  deps/ns_babysitter/ebin
  deps/ns_ssl_proxy/ebin)
EXECUTE_PROCESS (RESULT_VARIABLE _failure
  COMMAND dialyzer --plt "${COUCHBASE_PLT}" ${DIALYZER_FLAGS}
  --apps ${beamfiles}
  deps/ale/ebin
  ${COUCHDB_SRC}/src/couchdb ${COUCHDB_SRC}/src/couch_set_view ${COUCHDB_SRC}/src/couch_view_parser
  ${COUCHDB_SRC}/src/couch_index_merger/ebin
  ${_real_couchdb_src}/src/mapreduce
  deps/ns_babysitter/ebin
  deps/ns_ssl_proxy/ebin)
IF (_failure)
  MESSAGE (FATAL_ERROR "failed running dialyzer")
ENDIF (_failure)
