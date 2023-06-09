cmake_minimum_required(VERSION 3.20)
enable_language(CXX)

option(GEN_ONLY "dont run the build action after generating the build folder for each external dependency" FALSE)

# get path of install / extern
get_filename_component(ci_dir     "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(parent_dir "${ci_dir}"                  DIRECTORY)
#
set(INSTALL_PREFIX  "${parent_dir}/install")
set(CI_DIR          "${parent_dir}/ci")
set(EXTERN_DIR      "${parent_dir}/extern")
set(COMPILABLE_EXTS ".cpp .cc .c .cxx .ixx")

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug")
endif()

if(WIN32)
    add_link_options(/ignore:4098)
    set (CMAKE_SYSTEM_VERSION 10.0.20348.0)
    #add_compile_options(/p:CharacterSet=Unicode)
endif()

if (DEFINED DefsGuard)
    return()
endif()
set(DefsGuard yes)

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

macro(set_defs)
    set(CMAKE_SUPPRESS_REGENERATION false)

    if(MSVC)
        # MD = required for c++ 23 modules
        add_compile_options(/bigobj)
        add_compile_options(
            $<$<CONFIG:>:/MD>
            $<$<CONFIG:Debug>:/MD>
            $<$<CONFIG:Release>:/MD>
        )
    endif()

    set_default(ARCH      ${CMAKE_HOST_SYSTEM_PROCESSOR}) # "x64")
    set_default(EXTERN    "link")
    set_default(LINK      "static")
    set_default(PREFIX    "/usr/local")
    set_default(SDK       "native")

    
    if(CMAKE_BUILD_TYPE MATCHES Debug)
        set(DEBUG TRUE)
    else()
        set(DEBUG FALSE)
    endif()
    
    if(NOT SDK STREQUAL "native")
        if(NOT DEFINED ENV{STAGING_DIR})
            message(FATAL_ERROR "STAGING_DIR not set")
        endif()
        set(CMAKE_STAGING_PREFIX    $ENV{STAGING_DIR})
        set(PREFIX                  $ENV{STAGING_DIR})
        set(CMAKE_SYSROOT           ${PREFIX})
        set(CMAKE_SYSTEM_NAME       Linux)
        set(CMAKE_SYSTEM_PROCESSOR  ${ARCH})
        set(COMPILER_SUFFIX         "gnu")
        if(ARCH STREQUAL "arm")
            set(COMPILER_SUFFIX "gnuebi")
        endif()
        set(location                ${PREFIX}/bin/${ARCH}-${SDK}-linux-${COMPILER_SUFFIX})
        set(CMAKE_C_COMPILER        ${location}-gcc)
        set(CMAKE_CXX_COMPILER      ${location}-g++)
        set(CMAKE_RAN_LIB           ${location}-ranlib)
        set(CMAKE_RAN_NM            ${location}-nm)
        set(CMAKE_RAN_AR            ${location}-ar)
        set(CMAKE_RAN_STRIP         ${location}-strip)
        set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
        set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
        set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
        set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
    endif()

    if(NOT SDK STREQUAL "native")
        set(OS ${SDK})
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

    find_package(PkgConfig QUIET)
    set_property(GLOBAL PROPERTY RULE_MESSAGES OFF)
    add_definitions(-DEXTERN=link -DLINK=static -DARCH=x64 -DSDK=native)

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
        #add_compile_options(-fmodules --precompile) -- this is just a non starter because it has to be different for differnet sources
        if(x64 AND native)
            add_compile_options(-mavx2)
        endif()
        #add_compile_options(
        #    -Wall -Wfatal-errors  -Wno-strict-aliasing
        #    -fpic -funwind-tables -fvisibility=hidden -pipe)
    else()
        # base CXX flags for msvc (using 2022 with experimental build tools)
        # /module:stdIfcDir \"C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Tools\\MSVC\\14.33.31629\\ifc\\x64\\\"
        #set(CMAKE_CXX_FLAGS /experimental:module /sdl- /EHsc /MD) # /p:CharacterSet=Unicode 
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
            list(REMOVE_ITEM ${n} ${prefix}${aa})
        else()
            set(${n} ${${n}} ${prefix}${a})
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

macro(src)
    listy(src "" ${ARGN})
endmacro()

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

macro(lflags)
    listy(lflags "" ${ARGN})
endmacro()
