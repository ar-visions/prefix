# automake wrapper
# --------------------------------------------------

# [sync] run autoreconf -i to generate the configure script
execute_process(COMMAND autoreconf "-i" RESULT_VARIABLE autoreconf WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})

if (autoreconf STREQUAL "0")
    # [sync] run configure
    execute_process(COMMAND sh "./configure" "--prefix=${CMAKE_INSTALL_PREFIX}"
        RESULT_VARIABLE configure WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
    if(NOT configure EQUAL 0)
        message(FATAL_ERROR "configure script failed")
    endif()
else()
    message(FATAL_ERROR "autoreconf -i failed: exit-code ${autoreconf}")
endif()

# [async: make]    make
add_custom_target(run_make ALL COMMAND make WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})

# [async: install] make install
install(CODE "execute_process(COMMAND make install WORKING_DIRECTORY \"${CMAKE_SOURCE_DIR}\")")