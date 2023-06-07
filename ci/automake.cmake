# automake wrapper
# --------------------------------------------------

execute_process(COMMAND autoreconf "-i" RESULT_VARIABLE autoreconf WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
execute_process(COMMAND sh "./configure" "--prefix=${CMAKE_INSTALL_PREFIX}"
    RESULT_VARIABLE configure WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
if(NOT configure EQUAL 0)
    message(FATAL_ERROR "configure script failed")
endif()

add_custom_target(
    run_make
    ALL
    COMMAND ${CMAKE_COMMAND} -E cmake_echo_color --cyan "make ..."
    COMMAND make
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
)

add_custom_command(
    TARGET install
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E cmake_echo_color --yellow "make install ..."
    COMMAND make install
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
)
