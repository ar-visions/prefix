cmake_minimum_required(VERSION 3.20)

if (DEFINED PackageGuard)
    return()
endif()
set(PackageGuard yes)

function(find_import name fields)
    sbeParseJson(package package_contents)
endfunction()
