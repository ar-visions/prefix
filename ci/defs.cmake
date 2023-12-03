cmake_minimum_required(VERSION 3.20)
enable_language(CXX)

option(GEN_ONLY "dont run the build action after generating the build folder for each external dependency" FALSE)

# get path of install / extern
get_filename_component(ci_dir     "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(prefix_dir "${ci_dir}"                  DIRECTORY)

macro(set_default v val)
    if(NOT ${v})
        set(${v} ${val})
    endif()
endmacro()

macro(set_if var cond val else_val)
    if(${cond})
        set(${var} ${val})
    else()
        set(${var} ${else_val})
    endif()
endmacro()

macro(exit c)
    print("exiting with code ${c}")
endmacro()

macro(set_defs)
    set(CMAKE_SUPPRESS_REGENERATION false)

    if(MSVC)
        # MD = required for c++ 23 modules
        #add_compile_options(/bigobj)
        add_compile_options(
            $<$<CONFIG:>:/MT>
            $<$<CONFIG:Debug>:/MT>
            $<$<CONFIG:Release>:/MT>
        )
    endif()

    set_default(ARCH      ${CMAKE_HOST_SYSTEM_PROCESSOR}) # "x64")
    set_default(LINK      "static")
    set_default(PREFIX    "/usr/local")
    set_default(SDK       "native")
    
    if(CMAKE_BUILD_TYPE MATCHES Debug)
        set(DEBUG TRUE)
    else()
        set(DEBUG FALSE)
    endif()

    # anything with an SDK specified will build linux IoT things
    if(NOT SDK STREQUAL "native")
        set(OS "linux")
    elseif(WIN32)
        set(OS "win")
    elseif(APPLE)
        set(OS "mac")
    else()
        set(OS "linux")
    endif()

    set(${ARCH}   "1")
    set(${LINK}   "1")
    set(${EXTERN} "1")
    set(${SDK}    "1")
    set(${OS}     "1")
    set(cpp        23)

    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(cfg_lower "debug")
    else()
        set(cfg_lower "release")
    endif()

    # useful directories
    set(INSTALL_PREFIX  "${prefix_dir}/install/${SDK}-${cfg_lower}")
    set(CI_DIR          "${prefix_dir}/ci")
    set(EXTERN_DIR      "${prefix_dir}/extern")

    # determine if modules are compilable by looking for these exts
    set(COMPILABLE_EXTS ".cpp .cc .c .cxx .ixx .mm")

    #if(NOT CMAKE_BUILD_TYPE)
    #    set(CMAKE_BUILD_TYPE "Debug")
    #endif()

    if(WIN32)
        add_link_options(/ignore:4098)
        set(CMAKE_SYSTEM_VERSION 10.0.22000.0)
        set(CMAKE_LIBRARY_PATH "C:/Program Files (x86)/Windows Kits/10/Lib/10.0.22000.0/um/x64")
        #add_compile_options(/p:CharacterSet=Unicode)
    endif()


    find_package(PkgConfig QUIET)
    set_property(GLOBAL PROPERTY RULE_MESSAGES OFF)
    add_definitions(-DLINK=static -DARCH=x64 -DSDK=native)

    if(APPLE)
        set(m_pre                       "lib")
        set(m_lib                       ".a")
        set(m_lib2                      ".la")
        set(m_dyn                       ".dylib")
        set(app_ext                     "")
        set(lib_ext_extra               ".lib")
        file(GLOB BINS RELATIVE         "${CMAKE_CURRENT_SOURCE_DIR}" "build/*")
        set_source_files_properties(${BINS} PROPERTIES XCODE_EXPLICIT_FILE_TYPE "compiled")
    elseif(WIN32)
        set(m_pre                       "")
        set(m_lib                       ".lib")
        set(m_lib2                      ".lib")
        set(m_dyn                       ".dll")
        set(app_ext                     ".exe")
        set(lib_ext_extra               ".lib")
    else()
        set(m_pre                       "lib")
        set(m_lib                       ".a")
        set(m_lib2                      ".la")
        set(m_dyn                       ".so")
        set(app_ext                     "")
        set(lib_ext_extra               ".lib")
    endif()

    if (CMAKE_CXX_COMPILER_ID     STREQUAL "Clang")
        set(Clang "1")
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        set(GCC "1")
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
        set(ICC "1")
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        set(MSVC "1")
    endif()

    string(TOUPPER ${ARCH}              UARCH)
   #set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    set(CMAKE_CXX_STANDARD_REQUIRED     ON)
    set(CMAKE_CXX_EXTENSIONS           OFF)

    # default to C++ extensions being off.
    # clang's modules support have trouble with extensions right now.
    # ------------------------------------
    set(CMAKE_C_STANDARD                11)
    set(CMAKE_CXX_STANDARD              17)

    if(NOT MSVC)
        #set(CMAKE_CXX_FLAGS -fmodules)
        #add_compile_options(-fmodules --precompile)
        if(x64 AND native)
            add_compile_options(-mavx)
        endif()
        #add_compile_options(
        #    -Wall -Wfatal-errors  -Wno-strict-aliasing
        #    -fpic -funwind-tables -fvisibility=hidden -pipe)
    else()
        add_compile_options(/arch:AVX)
    endif()
endmacro()

macro(subdirs result curdir)
    file(GLOB children RELATIVE ${curdir} ${curdir}/*)
    set(dirlist "")
    foreach(child ${children})
    if(IS_DIRECTORY ${curdir}/${child})
        list(APPEND dirlist ${child})
    endif()
    endforeach()
    set(${result} ${dirlist})
endmacro()

macro(listy n prefix)
    foreach(a ${ARGN})
        string(SUBSTRING ${a} 0 1 f)
        if(f STREQUAL "+")
            string(SUBSTRING ${a} 1 -1 aa)
            set(${n} ${${n}} ${prefix}${aa})
        elseif(f STREQUAL "-")
            string(SUBSTRING ${a} 1 -1 aa)
            foreach(item ${${n}})
                string(FIND "${item}" "${prefix}${aa}" position REVERSE)
                if(position GREATER -1)
                    print("removing item: ${item}, matches ${prefix}${aa}")
                    list(REMOVE_ITEM ${n} ${item})
                endif()
            endforeach()
        else()
            set(${n} ${${n}} ${prefix}${a}) # we could use ADD_ITEM for clarity
        endif()
    endforeach()
endmacro()

macro(dep)
    listy(dep "" ${ARGN})
endmacro()

# this needs some additional processing for setting strings, but you can - remove defs.  to me thats intuitive, it just needs a :"string" :integer, etc
macro(defines)
    listy(_defines "" ${ARGN})
endmacro()

macro(lib_paths)
    listy(lib_paths "" ${ARGN})
endmacro()

macro(arch)
    listy(arch "" ${ARGN})
endmacro()

macro(apps)
    listy(apps "" ${ARGN})
endmacro()

function(src)
    list(GET ARGN 0 n)
    string(FIND ${n} "*" index)
    
    if(index GREATER -1)
        file(GLOB files ${n})
        foreach(f ${files})
            list(APPEND _src "${f}")
        endforeach()
    else()
        listy(_src "" ${ARGN})
    endif()

    set(_src ${_src} PARENT_SCOPE)
endfunction()

macro(artifacts)
    listy(_artifacts "" ${ARGN})
endmacro()

macro(includes)
    listy(includes "" ${ARGN})
endmacro()

macro(tests)
    listy(tests "" ${ARGN})
endmacro()

macro(cflags)
    listy(cflags "" ${ARGN})
endmacro()

macro(cxxflags)
    listy(cxxflags "" ${ARGN})
endmacro()

macro(lflags)
    listy(lflags "" ${ARGN})
endmacro()
