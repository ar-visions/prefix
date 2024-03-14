cmake_minimum_required(VERSION 3.20)

include(../prefix/ci/json.cmake)
include(../prefix/ci/defs.cmake)
include(../prefix/ci/module.cmake)
include(../prefix/ci/package.cmake)
## include(../prefix/ci/cxx20.cmake)

macro(assert COND DESC)
    if(NOT ${COND})
        message(FATAL_ERROR "assertion failure: " ${DESC})
    endif()
endmacro()

macro(assert_exists FILE DESC)
    if(NOT EXISTS ${FILE})
        message(FATAL_ERROR "file not found: " ${DESC})
    endif()
endmacro()

# install python from source on windows
macro(bootstrap_python)
    set_if(EXT WIN32 ".EXE" "")
    set_if(SLA WIN32 "/"   "/")
    set_if(SEP WIN32 "\;"   ":")

    find_program(PYTHON_EXECUTABLE python3)

    if(PYTHON_EXECUTABLE)
        set(PYTHON python3${EXT}) # python executable
        set(PIP    pip${EXT})    # pip executable
    else()
        ## this feature is not finished
        message(FATAL_ERROR "python required currently; feature to bootstrap from source requires wolfssl integration instead of openssl (which requires perl blah next -> wolfssl patch)")

        ## some variables
        set(PYTHON_VERSION "3.8.5")
        set(RES_DIR        ${CMAKE_CURRENT_BINARY_DIR}/io/res)           # local location of io resources
        set(PYTHON_SRC     ${RES_DIR}/Python-${PYTHON_VERSION}.zip)      # local location of source
        set(PYTHON_PATH    ${CMAKE_BINARY_DIR}/python-${PYTHON_VERSION}) # path once extracted to bin dir
        set(PYTHON         ${PYTHON_PATH}/python${EXT})                  # python executable
        set(PIP            ${PYTHON_PATH}/Scripts/pip${EXT})             # pip executable

        ## terrible thing
        set(ENV{PATH} "${PYTHON_PATH}${SEP}${PYTHON_PATH}${SLA}Scripts${SEP}$ENV{PATH}")
        
        ## make extern directory
        execute_process(COMMAND cmake -E make_directory extern)

        ## if python binary does not exist:
        if(NOT EXISTS ${PYTHON})

            ## clone wolfssl for python (its changed around to use it)
            if(NOT EXISTS extern/wolfssl)
                execute_process(COMMAND git clone "https://github.com/wolfSSL/wolfssl.git" ${EXTERN_DIR}/wolfssl)
                execute_process(COMMAND configure WORKING_DIRECTORY extern/wolfssl)
            endif()

            ## io resources
            if(NOT EXISTS extern/io)
                execute_process(COMMAND git clone "https://github.com/ar-visions/ar-visions.github.io" ${EXTERN_DIR}/io)
            endif()

            ## extract python source
            file(ARCHIVE_EXTRACT INPUT ${PYTHON_SRC} DESTINATION ${CMAKE_BINARY_DIR})

            ## verify pip exists, and thus extraction occurred 
            assert_exists(${PIP} "pip")

            ## python must exist to proceed
            assert_exists(${PYTHON} "python not found")
        endif()

        ## install pip packages on either built python, or system
        foreach(pkg ${ARGV})
            message(STATUS "installing pip package: ${pkg} (${PIP})")
            message(STATUS "ENV: " $ENV{PATH})
            execute_process(COMMAND ${PIP} install ${pkg} RESULT_VARIABLE pkg_res)
            message(STATUS "result: ${pkg_res}")
        endforeach()
    endif()
endmacro()

function(main)
    set_defs()

    ## extend cmake to do a bit more importing and building if it has not been done yet
    ## do it in the configuration made by the user and in the output directory of the user
    set(ENV{CMAKE_C_COMPILER}   ${CMAKE_C_COMPILER})
    set(ENV{CMAKE_CXX_COMPILER} ${CMAKE_CXX_COMPILER})
    set(ENV{CMAKE_SOURCE_DIR}   ${CMAKE_SOURCE_DIR})
    set(ENV{CMAKE_BINARY_DIR}   ${CMAKE_BINARY_DIR})
    set(ENV{CMAKE_BUILD_TYPE}   ${CMAKE_BUILD_TYPE})
    set(ENV{JSON_IMPORT_INDEX}  ${CMAKE_BINARY_DIR}/import.json)
    set(ENV{JSON_SDK_INDEX}     ${CMAKE_BINARY_DIR}/sdk.json)
    set(ENV{GEN_ONLY}           ${GEN_ONLY})

    # bootstrap python with pip packages
    bootstrap_python(requests)

    # now that we have prepared python.. we can run prefix.py (clone build & install externs)
    execute_process(
        COMMAND ${PYTHON} "${prefix_dir}/ci/prefix.py" RESULT_VARIABLE import_result)

    # its written to and valid if this import_result equals 0, no need to delete
    if (NOT (import_result EQUAL "0"))
        message(FATAL_ERROR "could not import dependencies for project ${r_path} (code: ${import_result})")
    endif()

    file(READ $ENV{JSON_IMPORT_INDEX} import_contents)
    sbeParseJson(import_index import_contents)

    set(imports "" CACHE INTERNAL "")

    set(i 0)
    while(true)
        set(s_entry "${import_index_${i}}"      CACHE INTERNAL "")
        set(n_entry "${import_index_${i}.name}" CACHE INTERNAL "")

        if (s_entry)
            list(APPEND imports ${s_entry})
            set(import.${s_entry}          ${s_entry} CACHE INTERNAL "")
            set(import.${s_entry}.extern   ${EXTERN_DIR}/${s_entry} CACHE INTERNAL "")
            set(import.${s_entry}.peer     true  CACHE INTERNAL "")
            set(import.${s_entry}.version  "dev" CACHE INTERNAL "")
            
        elseif(n_entry)
            list(APPEND imports ${n_entry})
            set(import.${n_entry}          ${n_entry} CACHE INTERNAL "")
            set(import.${n_entry}.peer     false CACHE INTERNAL "")
            set(import.${n_entry}.version  ${import_index_${i}.version} CACHE INTERNAL "")
            set(import.${n_entry}.url      ${import_index_${i}.url} CACHE INTERNAL "")
            set(import.${n_entry}.commit   ${import_index_${i}.commit} CACHE INTERNAL "")
            set(import.${n_entry}.includes "" CACHE INTERNAL "")
            set(import.${n_entry}.libs     "" CACHE INTERNAL "")
            set(import.${n_entry}.bins     "" CACHE INTERNAL "")
            set(import.${n_entry}.extern   ${EXTERN_DIR}/${n_entry}-${import_index_${i}.version} CACHE INTERNAL "")

            # add include paths
            set(ii 0)
            while(true)
                #message(STATUS "checking import.${n_entry}.includes += ${import_index_${i}.includes_${ii}}")
                set(include ${import_index_${i}.includes_${ii}} CACHE INTERNAL "")
                if(NOT include)
                    break()
                endif()
                if (EXISTS ${include})
                    print("including sdk: ${include}")
                    list(APPEND import.${n_entry}.includes ${include})
                else()
                    set(loc ${import.${n_entry}.extern}/${include})
                    get_filename_component(resolve ${loc} REALPATH)
                    list(APPEND import.${n_entry}.includes ${resolve})
                endif()
                math(EXPR ii "${ii} + 1")
            endwhile()

            # add lib paths
            set(ii 0)
            while(true)
                set(lib ${import_index_${i}.libs_${ii}})
                if(NOT lib)
                    break()
                endif()
                # if there is an absolute location specified to libs
                if (EXISTS ${lib})
                    print("sdk libs: ${lib}")
                    list(APPEND import.${n_entry}.libs ${lib})
                else()
                    print("adding relative lib: ${lib}")
                    # msvc has one additional dir which is switched on standard CMAKE_BUILD_TYPE
                    # env var passed to prepare.py, passed onto external cmake projects
                    set(extra "")
                    if(MSVC)
                        set(extra "/Release")
                        if(DEBUG)
                            set(extra "/Debug")
                        endif()
                    endif()
                    list(APPEND import.${n_entry}.libs ${import.${n_entry}.extern}/${lib}${extra}) # probably better to translate in the prepare.py (bin is doing this)
                endif()

                math(EXPR ii "${ii} + 1")
            endwhile()

            set(ii 0)
            while(true)
                set(bin ${import_index_${i}.bins_${ii}})
                if(NOT bin)
                    break()
                endif()
                list(APPEND import.${n_entry}.bins ${bin})
                math(EXPR ii "${ii} + 1")
            endwhile()
        else()
            break()
        endif()
        math(EXPR i "${i} + 1")
    endwhile()

    # load external projects first for dependency ordering
    foreach(import ${imports})
        if(import.${import}.peer)
            set(project_loc ${import.${import}.extern})
            get_filename_component(resolve ${project_loc} REALPATH)
            print("project resolve: ${project_loc} -> ${resolve}")
            load_project(${resolve} ${import})
        endif()
    endforeach()

    # load this project [json index is read inside]
    load_project(${CMAKE_CURRENT_SOURCE_DIR} "")
endfunction()
