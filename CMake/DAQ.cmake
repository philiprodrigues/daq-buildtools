
function( point_build_to output_dir )

  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${PROJECT_NAME}/${output_dir} PARENT_SCOPE)
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${PROJECT_NAME}/${output_dir} PARENT_SCOPE)
  set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${PROJECT_NAME}/${output_dir} PARENT_SCOPE)

endfunction()

function(add_unit_test testname)

  add_executable( ${testname} unittest/${testname}.cxx )
  target_link_libraries( ${testname} ${DAQ_LIBRARIES_UNIVERSAL_EXE} ${DAQ_LIBRARIES_PACKAGE}  ${Boost_UNIT_TEST_FRAMEWORK_LIBRARY} )
  target_include_directories( ${testname} SYSTEM PRIVATE ${DAQ_INCLUDES_UNIVERSAL})
  target_compile_definitions(${testname} PRIVATE "BOOST_TEST_DYN_LINK=1")
  add_test(NAME ${testname} COMMAND ${testname})

endfunction()