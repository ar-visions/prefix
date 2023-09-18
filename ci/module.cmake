cmake_minimum_required(VERSION 3.20)

if (DEFINED ModuleGuard)
    return()
endif()
set(ModuleGuard yes)

# apple has been quiet about this too but thats an aside
if(NOT APPLE)
    find_package(CUDAToolkit QUIET)
endif()

macro(cpp ver)
    set(cpp ${ver})
endmacro()

macro(cstd ver)
    set(cstd ${ver})
endmacro()

#set_property(GLOBAL PROPERTY GLOBAL_DEPENDS_DEBUG_MODE 1)
 
# generate some C source for version
function(set_version_source p_name p_version)
    set(v_src ${CMAKE_BINARY_DIR}/${p_name}-version.cpp)
    if(NOT ${p_name}-version-output)
        set_if(fn_attrs WIN32 "" "__attribute__((visibility(\"default\")))")
        string(TOUPPER ${p_name} u)
        string(REPLACE "-" "_"   u ${u})
        set(c_src "extern ${fn_attrs} const char *${u}_VERSION() { return \"${p_version}\"\; }")
        file(WRITE ${v_src} ${c_src})
        set(${p_name}-version-output TRUE)
    endif()
endfunction()

# standard module includes
macro(module_includes t r_path mod)
    #target_include_directories(${t} PRIVATE ${r_path}/${mod})
    #if(EXISTS "${r_path}/${mod}/include")
    #    target_include_directories(${t} PRIVATE ${r_path}/${mod}/include)
    #endif()
    target_include_directories(${t} PRIVATE ${r_path})
    target_include_directories(${t} PRIVATE ${CMAKE_BINARY_DIR})
    # will likely still need a system include
    target_include_directories(${t} PRIVATE "${INSTALL_PREFIX}/include")
endmacro()

macro(set_compilation t mod)
    target_compile_options(${t} PUBLIC ${CMAKE_CXX_FLAGS} ${cflags})
    if(Clang)
        target_compile_options(${t} PRIVATE -Wfatal-errors)
    endif()
    target_link_options       (${t} PRIVATE ${lflags})
    target_compile_definitions(${t} PRIVATE ARCH_${UARCH})
    target_compile_definitions(${t} PRIVATE  UNICODE)
    target_compile_definitions(${t} PRIVATE _UNICODE)
    target_compile_definitions(${t} PRIVATE ${_defines})
endmacro()

macro(app_source app)
    if (NOT external_repo)
        listy(${app}_source "${mod}/apps/" ${ARGN})
    else()
        listy(${app}_source "${r_path}/${mod}/apps/" ${ARGN})
    endif()
endmacro()

macro(skip)
    set(_skip TRUE)
endmacro()

macro(var_prepare r_path)
    set(module_path     "${r_path}/${mod}")
    set(module_file     "${module_path}/mod")
    set(arch            "")
    set(cflags          "")
    set(lflags          "")
    #set(roles "")
    set(dep             "")
    set(_skip           FALSE)
    set(lib_paths       "")
    set(includes        "")
    set(_artifacts      "")
    set(_defines        "")
    set(_src            "")
    set(_headers        "")
    set(_apps_src       "")
    set(_tests_src      "")
    set(cpp             20)
    set(cstd            99)
    set(p "${module_path}")

    # compile these as c++-module (.ixx extension) (unix/mac only for g++)
    if(NOT WIN32)
        #file(GLOB _src_0 "${p}/*.ixx")
        #foreach(isrc ${_src_0})
        #    set_source_files_properties(${isrc} PROPERTIES LANGUAGE CXX COMPILE_FLAGS "-x c++-module")
        #endforeach()
    endif()

    # pch (alias: {mod}.hpp) and module cases
    if(EXISTS "${p}/${mod}.ixx" OR EXISTS "${p}/${mod}.cpp")
        file(GLOB        _src "${p}/*.ixx" "${p}/*.c*" "${p}/*.mm")
        list(REMOVE_ITEM _src "${p}/${mod}.ixx")
        list(REMOVE_ITEM _src "${p}/${mod}.cpp")
        ##
        if(EXISTS "${p}/${mod}.cpp")
            list(INSERT _src 0 "${p}/${mod}.cpp")
        endif()
        ##
        if(EXISTS "${p}/${mod}.mm")
            list(INSERT _src 0 "${p}/${mod}.mm")
        endif()
        ##
        if(EXISTS "${p}/${mod}.ixx")
            list(INSERT _src 0 "${p}/${mod}.ixx")
        endif()
    else()
        file(GLOB _src "${p}/*.ixx" "${p}/*.c*" "${p}/*.mm")
        if(EXISTS "${p}/${mod}.cpp")
            list(REMOVE_ITEM _src "${p}/${mod}.cpp")
        endif()
    endif()

    file(GLOB _headers           "${p}/*.h*")
    if(EXISTS                    "${p}/apps")
        file(GLOB _apps_src      "${p}/apps/*.c*" "${p}/apps/*.mm")
        file(GLOB _apps_headers  "${p}/apps/*.h*")
    endif()
    if(EXISTS                    "${p}/tests")
        file(GLOB _tests_src     "${p}/tests/*.c*")
        file(GLOB _tests_headers "${p}/tests/*.h*")
    endif()
    
    # list of header-dirs
    set(headers "")
    foreach(s ${_headers})
        get_filename_component(name ${s} NAME)
        list(APPEND headers ${name})
    endforeach()

    # compile for 17 by default
    set(cpp 17)
    set(dynamic false)

    # list of app targets
    set(apps "")
    foreach(s ${_apps_src})
        get_filename_component(name ${s} NAME)
        list(APPEND apps ${name})
    endforeach()
    
    # list of header-dirs for apps (all)
    set(apps_headers "")
    foreach(s ${_apps_headers})
        get_filename_component(name ${s} NAME)
        list(APPEND apps_headers ${name})
    endforeach()
    
    # list of test targets
    set(tests "")
    foreach(s ${_tests_src})
        get_filename_component(name ${s} NAME)
        list(APPEND tests ${name})
    endforeach()
    set(tests_headers "")
    foreach(s ${_tests_headers})
        get_filename_component(name ${s} NAME)
        list(APPEND tests_headers ${name})
    endforeach()

endmacro()

# resolve a list of symlinks so vscode is not confused anymore
function(resolve_symlinks input_list output_list)
    set(resolved_list "")
    foreach(src ${${input_list}})
        get_filename_component(resolved_path ${src} REALPATH)
        #print("resolve: ${src} -> ${resolved_path}")
        list(APPEND resolved_list ${resolved_path})
    endforeach()
    set(${output_list} ${resolved_list} PARENT_SCOPE)
endfunction()

macro(var_finish)

    # ------------------------
    list(APPEND m_list ${mod})
    list(FIND arch ${ARCH} arch_found)
    if(arch AND arch_found EQUAL -1)
        set(br TRUE)
        return()
    endif()

    # ------------------------
    set(full_src "")
    foreach(n ${_src})
        if(EXISTS ${n})
            list(APPEND full_src "${n}")
        else()
            list(APPEND full_src "${p}/${n}")
        endif()
    endforeach()

    # h_list (deprecate)
    # ------------------------
    set(h_list "")
    foreach(n ${headers})
        list(APPEND h_list "${p}/${n}")
        list(APPEND full_src "${p}/${n}")
    endforeach()

    # expand lists with wildcards on src, support explicit src too.

    # expand artifacts (misc sources we depend on)
    foreach(a ${_artifacts})
        string(FIND ${a} "*" star_position)
        if (star_position EQUAL -1)
            source_group("Resources" FILES "${p}/${a}")
            list(APPEND _src "${p}/${a}")
            list(APPEND full_src "${p}/${a}")
        else()
            file(GLOB glob ${a})
            foreach(aa ${glob})
                source_group("Resources" FILES "${p}/${aa}")
                list(APPEND _src "${p}/${aa}")
                list(APPEND full_src "${p}/${aa}")
            endforeach()
        endif()
    endforeach()

    # resolve this full_src list
    resolve_symlinks(full_src full_src)
    set(full_includes "")

    # add prefixed location if it exists
    # ------------------------
    if(EXISTS "${CMAKE_INSTALL_PREFIX}/include")
        # prefix takes precedence over system
        #print("sys includes: ${CMAKE_INSTALL_PREFIX}/include")
        list(APPEND full_includes "${CMAKE_INSTALL_PREFIX}/include")
    endif()

    if(EXISTS "${INSTALL_PREFIX}/include")
        #print("install includes: ${INSTALL_PREFIX}/include")
        list(APPEND full_includes "${INSTALL_PREFIX}/include")
    endif()

    # handle includes by preferring abs path, then relative to prefix-path
    # ------------------------
    foreach(n ${includes})
        # ------------------------
        # abs path n exists
        # ------------------------
        if(EXISTS ${n})
            #message("include: ${n}")
            list(APPEND full_includes ${n})
            # /usr/local/include/n exists (system-include)
            # ------------------------
        elseif(EXISTS "${INSTALL_PREFIX}/include/${n}")
            message("include (prefix): ${n}")
            list(APPEND full_includes "${INSTALL_PREFIX}/include/${n}")
        else()
            # include must be found; otherwise its indication of error
            # ------------------------
            message(FATAL_ERROR "couldnt find include path for symbol: ${n}")
        endif()
    endforeach()
endmacro()

function(get_name location name)
    file(READ ${location} package_contents)
    sbeParseJson(package package_contents)
    set(${name} ${package.name} PARENT_SCOPE)
endfunction()

# name name_ucase version imports
function(read_project_json location name name_ucase version)
    file(READ ${location} package_contents)
    if(NOT package_contents)
        message(FATAL_ERROR "project.json not in package root")
    endif()

    ## parse json with sbe-parser (GPLv3)
    sbeParseJson(package package_contents)

    set(${name}    ${package.name}    PARENT_SCOPE)
    set(${version} ${package.version} PARENT_SCOPE)
    
    ## format the package-name from this-case to THIS_CASE
    string(TOUPPER       ${package.name}    pkg_name_ucase)
    string(REPLACE "-" "_" pkg_name_ucase ${pkg_name_ucase})

    if(name_ucase)
        set(${name_ucase} ${pkg_name_ucase} PARENT_SCOPE)
    endif()

    sbeClearJson(package)
endfunction()

macro(get_module_dirs src result)
    file(GLOB children RELATIVE ${src} "${src}/*")
    set(dirlist "")
    foreach(child ${children})
    if(IS_DIRECTORY "${src}/${child}" AND EXISTS "${src}/${child}/mod")
        list(APPEND dirlist ${child})
    endif()
    endforeach()
    set(${result} ${dirlist})
endmacro()

function(print text)
    message(STATUS ${text})
endfunction()

function(error text)
    message(FATAL_ERROR ${text})
endfunction()

function(load_project location remote)
    print("project: ${location}")
    # return right away if this project is not ion-oriented
    set(js ${location}/project.json)
    if(NOT EXISTS ${js})
        error("load_project could not find index: ${location} ${remote}")
        return()
    endif()

    # ------------------------
    read_project_json(${js} name name_ucase version)

    # fetch a list of all module dir stems (no path behind, no ./ or anything just the names)
    # ------------------------
    get_module_dirs(${location} module_dirs)

    # ------------------------
    set(m_list    "" PARENT_SCOPE)
    set(app_list  "" PARENT_SCOPE)
    set(test_list "" PARENT_SCOPE)

    # iterate through modules
    # ------------------------
    foreach(mod ${module_dirs})
        load_module(${location} ${name} ${mod} ${js})
    endforeach()
endfunction()

# select cmake package, target name, or framework
# can likely deprecate the target name case
function(select_library t_name d)
    set(linkage PRIVATE)

    if("${d}" MATCHES "^@")
        string(SUBSTRING ${d} 1 -1 substring)
        set(d ${substring})
        set(linkage PUBLIC)
    endif()

    find_package(${d} CONFIG QUIET)


    
    if(${d}_FOUND)
        if(TARGET ${d}::${d})
            #message(STATUS "(package) ${t_name} -> ${d}::${d}")
            target_link_libraries(${t_name} ${linkage} ${d}::${d})
        elseif(TARGET ${d})
            #message(STATUS "(package) ${t_name} -> ${d}")
            target_link_libraries(${t_name} ${linkage} ${d})
        endif()
        #
    elseif(TARGET ${d})
        #message(STATUS "(target) ${t_name} -> ${d}")
        target_link_libraries(${t_name} ${linkage} ${d})
        #set(${d}_DIR "system" CACHE INTERNAL "") # quiet up cmake
    else()
        find_package(${d} QUIET)
        if(${d}_FOUND)
            #message(STATUS "(package) ${t_name} -> ${d}")
            if(TARGET ${d}::${d})
                target_link_libraries(${t_name} ${linkage} ${d}::${d})
            elseif(TARGET ${d})
                target_link_libraries(${t_name} ${linkage} ${d})
            endif()
        else()
            find_library(${d}_FW QUIET)
            if(NOT ${d}_FW STREQUAL "system") # i forget why we had _FW lookups; deprecate
                if(${d}_FW)
                    message(STATUS "(framework) ${t_name} -> ${${d}_FW}")
                    target_link_libraries(${t_name} ${linkage} ${${d}_FW})
                else()
                    #message(STATUS "(system) ${t_name} -> ${d}")
                    target_link_libraries(${t_name} ${linkage} ${d})
                    #set(${d}_FW "system" CACHE INTERNAL "") # quiet up cmake
                endif()
                #set(${d}_DIR "system" CACHE INTERNAL "") # quiet up cmake
            endif()
        endif()
        #
    endif()
endfunction()

## process single dependency
## ------------------------
macro(process_dep d t_name)
    ## find 'dot', this indicates a module is referenced (peer modules should be referenced by project)
    ## ------------------------
    string(FIND ${d} ":" index)

    ## project.module supported when the project is imported by peer extension or git relationship
    ## ------------------------
    if(index GREATER 0)
        ## get project name
        string(SUBSTRING  ${d} 0 ${index} project)
        math(EXPR index   "${index}+1")
        string(SUBSTRING  ${d} ${index} -1 module)        
        set(pkg_path      "")

        ## path to source (not pre-built imports) is either itself or a symlink in external (for attempt 1)
        if (${PROJECT_NAME} STREQUAL ${project})
            set(extern_path ${CMAKE_SOURCE_DIR})
            set(pkg_path    ${CMAKE_SOURCE_DIR}/project.json)
        else()
            # in cmake, we must resolve all symlinks otherwise 'users' of the compilation output and/or debug file locations get it a bit wrong
            set(extern_path ${EXTERN_DIR}/${project}) # projects in externs without versions are peers
            set(pkg_path    ${EXTERN_DIR}/${project}/project.json)
            get_filename_component(extern_path ${extern_path} REALPATH)
            get_filename_component(pkg_path    ${pkg_path}    REALPATH)
        endif()

        # if module-based project (a prefix schema)
        if(EXISTS ${pkg_path})
            set(mod_target ${project}-${module})

            # recursion restricted to project's modules
            # integrity error if it does not exist otherwise (should exist with external import ordering)
            if(project STREQUAL "${project_name}")
                if(NOT TARGET ${mod_target})
                    print("generation reordering: ${module}")
                    load_module(${r_path} ${project_name} ${module} ${pkg_path})
                endif()
                # should be valid target now..
            endif()
            
            get_target_property(t_type ${mod_target} TYPE)
            if(t_type MATCHES ".*_LIBRARY$")
                target_link_libraries(${t_name} PRIVATE ${mod_target})
                target_include_directories(${t_name} PUBLIC ${extern_path})
                #print("target_include_directories ${t_name} -> ${extern_path}")
            endif()
        else()
            set(found FALSE)
            foreach (import ${imports})
                if ("${import}" STREQUAL "${project}")
                    ## add lib paths for this external
                    foreach (i ${import.${import}.libs})
                        if (EXISTS ${i})
                            link_directories(${t_name} ${i})
                        else()
                            error("lib path does not exist: ${i}")
                        endif()
                    endforeach()

                    ## prefix.py needs to be set as Resource, would need to be associated to a build module
                    ## its probably a good idea to have the mods have src(../ci/prefix.py)
                    ## symlink bins into CMAKE_BINARY_DIR; having a PATH for this doesnt work
                    foreach (bin_dir ${import.${import}.bins})
                        file(GLOB bin_files "${bin_dir}/*")
                        
                        foreach(bin_file ${bin_files})
                            get_filename_component(file_name ${bin_file} NAME)
                            set_if(CMD ${DEBUG} create_symlink copy)
                            add_custom_command(
                                TARGET  ${t_name} POST_BUILD
                                COMMAND ${CMAKE_COMMAND} -E ${CMD} ${bin_file} ${CMAKE_BINARY_DIR}/${file_name})
                        endforeach()
                    endforeach()

                    ## switch based on static/dynamic use-cases
                    ## private for shared libs and public for pass-through to exe linking
                    set_if(exposure dynamic "PRIVATE" "PUBLIC")
                    target_link_libraries(${t_name} ${exposure} ${module}) 
                    ## this was private and thats understandable, but apps that use this should also get it too
                    ## do env var replacement on include paths; vulkan one can be guessed and if its not there on init
                    if(${import.${import}.includes})
                        if (EXISTS ${import.${import}.includes})
                            target_include_directories(${t_name} PUBLIC ${import.${import}.includes})
                        else()
                            error("include path not found: ${import.${import}.includes}")
                        endif()
                    endif()
                    set(found TRUE)
                    break()
                endif()
            endforeach()
            if (NOT found)
                message(FATAL_ERROR "external module not found: (this project) ${PROJECT_NAME} project:module = ${project}:${module}")
            endif()
        endif()
    else()
        if(NOT WIN32)
            pkg_check_modules(PACKAGE QUIET ${d})
        endif()
        if(PACKAGE_FOUND)
            message(STATUS "pkg_check_modules QUIET -> (target): ${t_name} -> ${d}")
            target_link_libraries(${t_name}      PRIVATE ${PACKAGE_LINK_LIBRARIES})
            target_include_directories(${t_name} PRIVATE ${PACKAGE_INCLUDE_DIRS})
            target_compile_options(${t_name}     PRIVATE ${PACKAGE_CFLAGS_OTHER})
        else()
            select_library(${t_name} ${d})
        endif()
    endif()
endmacro()

macro(address_sanitizer t_name)
    # enable address sanitizer
    if (DEBUG)
        if (MSVC)
            #target_compile_options(${t_name} PRIVATE /fsanitize=address)
        else()
            # introduces linking errors in linux now; i think i havent used gcc with this yet, though
            #target_compile_options(${t_name} PRIVATE -fsanitize=address)
            #target_link_options(${t_name} PRIVATE -fsanitize=address)
        endif()
    endif()
endmacro()

# has extensions, useful thing.
function(contains_ext found exts src)
    separate_arguments(exts_list NATIVE_COMMAND ${exts})
    set(m "")
    set(${found} FALSE PARENT_SCOPE)
    foreach(e ${exts_list})
        if(m)
            set(m ${m}|\\${e}$)
        else()
            set(m \\${e}$)
        endif()
    endforeach()
    foreach(f ${src})
        if(f MATCHES ${m})
            #print("${f} matches ${m}")
            set(${found} TRUE PARENT_SCOPE)
            break()
        endif()
    endforeach()
endfunction()

macro(create_module_targets)
    set(v_src ${CMAKE_BINARY_DIR}/${t_name}-version.cpp)
    source_group("Resources" FILES ${js})
    set_version_source(${t_name} ${version})
    set(is_compilable FALSE)
    
    # compilable module checks, only when there is 'src' given
    # it may be script resources only; in that case you dont make targets
    if(full_src)
        contains_ext(is_compilable ${COMPILABLE_EXTS} ${full_src})
    endif()

    if (NOT is_compilable)
        add_custom_target(${t_name})
        print("non-compilable module: ${t_name}")
    else()
        if (dynamic)
            add_library(${t_name} ${h_list} ${js})
            if(cpp EQUAL 23)
                target_sources(${t_name}
                    PRIVATE
                        FILE_SET cxx_modules TYPE CXX_MODULES FILES
                        ${full_src})
            else()
                target_sources(${t_name} PRIVATE ${full_src} ${js})
            endif()
        elseif(static OR external_repo)
            add_library(${t_name} STATIC)
            if(cpp EQUAL 23)
                #target_sources(${t_name}
                #    PRIVATE
                #        FILE_SET cxx_modules TYPE CXX_MODULES
                #        FILES ${full_src} 
                #    INTERFACE
                #        FILE_SET headers TYPE HEADERS
                #        BASE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/${mod}"
                #        FILES ${h_list})
            else()
                #print("full src for target ${t_name}: ${full_src}")
                
                target_sources(${t_name} PRIVATE ${full_src} ${h_list} ${js})
            endif()
        else()
            message(FATAL_ERROR "!dynamic && !static")
        endif()
        
        if (WIN32)
            #add_compile_options(/bigobj)
        endif()
        address_sanitizer(${t_name})
        if (cpp EQUAL 23)
            if(MSVC)
                print("------------- C++ 23 for module ${t_name} -------------")
                target_compile_options(${t_name} PRIVATE /std:c++20 /experimental:module /sdl- /EHsc)
            endif()
            target_compile_features(${t_name} PRIVATE cxx_std_23)
        elseif(cpp EQUAL 14)
            target_compile_features(${t_name} PRIVATE cxx_std_14)
        elseif(cpp EQUAL 17)
            if(MSVC)
                target_compile_options (${t_name} PRIVATE /sdl- /EHsc)
            endif()
            target_compile_features(${t_name} PRIVATE cxx_std_17)
        elseif(cpp EQUAL 20)
            target_compile_features(${t_name} PRIVATE cxx_std_20)
        else()
            message(FATAL_ERROR "cpp version ${cpp} not supported")
        endif()

        if(full_includes)
            target_include_directories(${t_name} PUBLIC ${full_includes})
        endif()
        set_target_properties(${t_name} PROPERTIES LINKER_LANGUAGE CXX)

        # show module file in IDEs
        set_source_files_properties(${module_file} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
        source_group("Resources" FILES ${module_file})
        set_compilation(${t_name} ${mod})

        # accumulate resources in binary based on targets post-built
        # ------------------------
        if(EXISTS ${p}/res)
        
            add_custom_command(
                TARGET ${t_name} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${p}/res ${CMAKE_BINARY_DIR})

        endif()

        # test products
        # ------------------------
        foreach(test ${tests})
            # strip the file stem for its target name
            # ------------------------
            get_filename_component(e ${test} EXT)
            string(REGEX REPLACE "\\.[^.]*$" "" test_name ${test})
            set(test_file "${p}/tests/${test}")
            set(test_target ${test_name})
            list(APPEND test_list ${test})
            add_executable(${test_target} ${test_file})
        
            # add apps as additional include path, standard includes and compilation settings for module
            # ------------------------
            target_include_directories(${test_target} PRIVATE ${p}/apps)
            module_includes(${test_target} ${r_path} ${mod})
            set_compilation(${test_target} ${mod})
            target_link_libraries(${test_target} PRIVATE ${t_name})
            # ------------------------
            if(NOT TARGET test-${t_name})
                add_custom_target(test-${t_name})
                if (NOT TARGET test-all)
                    add_custom_target(test-all)
                endif()
                add_dependencies(test-all test-${t_name})
            endif()
        
        # add this test to the test-proj-mod target group
        # ------------------------
        add_dependencies(test-${t_name} ${test_target})
        
        endforeach()

        module_includes(${t_name} ${r_path} ${mod})
        #set_property(TARGET ${t_name} PROPERTY POSITION_INDEPENDENT_CODE ON) # not sure if we need it on with static here
        
        if(external_repo)
            set_target_properties(${t_name} PROPERTIES EXCLUDE_FROM_ALL TRUE)
        endif()

        target_sources(${t_name} PRIVATE ${module_file})
        target_link_directories(${t_name} PUBLIC ${INSTALL_PREFIX}/lib)

        # extra library paths
        foreach(p ${lib_paths})
            target_link_directories(${t_name} PUBLIC ${p})
        endforeach()

        if(dep)
            foreach(d ${dep})
                process_dep(${d} ${t_name})
            endforeach()
        endif()

        foreach(app ${apps})
            set(app_path "${p}/apps/${app}")
            string(REGEX REPLACE "\\.[^.]*$" "" t_app ${app})
            list(APPEND app_list ${t_app})
            
            # add app target
            if(cuda_add_executable)
                cuda_add_executable(${t_app} ${app_path} ${${t_app}_src})
            else()
                add_executable(${t_app} ${app_path} ${${t_app}_src}) # must be a setting per app, so store in map or something win32(+app)
            endif()
            
            address_sanitizer(${t_app})
            target_precompile_headers(${t_app} PRIVATE ${p}/${mod}.hpp)
            target_include_directories(${t_app} PRIVATE ${p}/apps)
            module_includes(${t_app} ${r_path} ${mod})
            set_compilation(${t_app} ${mod})
            string(TOUPPER ${t_app} u)
            string(REPLACE "-" "_" u ${u})

            target_compile_definitions(${t_app} PRIVATE APP_${u})
            target_link_libraries(${t_app} PRIVATE ${t_name}) # public?
            add_dependencies(${t_app} ${t_name})
            
        endforeach()
    endif()

endmacro()

# load module file for a given project (mod, placed in module-folders)
# ------------------------
function(load_module r_path project_name mod js)
    # create a target name for this module (t_name = project-module)
    set(t_name "${project_name}-${mod}")
    if(NOT TARGET ${t_name})
        var_prepare(${r_path})
        include(${module_file})
        var_finish()
        # call skip() to omit module on specific targets
        # nvvk and nvh are skipped on apple, for instance
        if(NOT _skip)
            create_module_targets()
        endif()
    endif()
endfunction()
