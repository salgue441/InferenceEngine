cmake_minimum_required(VERSION 3.25)

# Set project metadata
project(NeuraForge 
    VERSION 1.0.0 
    LANGUAGES CXX
    DESCRIPTION "High-performance C++20 neural inference engine"
    HOMEPAGE_URL "https://github.com/your-org/neuraforge")

# Set C++20 standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Include essential modules
include(GNUInstallDirs)
include(CMakePackageConfigHelpers)
include(CTest)

# Options
option(BUILD_SHARED_LIBS "Build shared libraries" OFF)
option(BUILD_TESTS "Build tests" ON)
option(BUILD_BENCHMARKS "Build benchmarks" ON)
option(BUILD_EXAMPLES "Build examples" ON)
option(BUILD_DOCS "Build documentation" OFF)
option(ENABLE_SANITIZERS "Enable sanitizers" OFF)
option(ENABLE_COVERAGE "Enable coverage reporting" OFF)
option(ENABLE_LTO "Enable Link Time Optimization" OFF)
option(ENABLE_CUDA "Enable CUDA support" OFF)
option(ENABLE_PROFILING "Enable profiling support" OFF)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")

# Find required packages
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)

# Core dependencies
find_package(Torch REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)
find_package(spdlog REQUIRED)
find_package(fmt REQUIRED)
find_package(TBB REQUIRED)
find_package(Protobuf REQUIRED)
find_package(nlohmann_json REQUIRED)

# Optional dependencies
if(BUILD_TESTS)
    find_package(Catch2 3 REQUIRED)
endif()

if(BUILD_BENCHMARKS)
    find_package(benchmark REQUIRED)
endif()

if(ENABLE_CUDA)
    find_package(CUDAToolkit REQUIRED)
endif()

# Compiler-specific settings
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(
        -Wall -Wextra -Wpedantic -Werror
        -Wno-unused-parameter
        -Wno-missing-field-initializers
    )
    
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        add_compile_options(-O3 -funroll-loops -fvectorize)
    endif()
    
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        add_compile_options(-g -O0)
    endif()
endif()

# Sanitizers
if(ENABLE_SANITIZERS AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_compile_options(-fsanitize=address,undefined)
    add_link_options(-fsanitize=address,undefined)
endif()

# Coverage
if(ENABLE_COVERAGE AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_compile_options(--coverage)
    add_link_options(--coverage)
endif()

# LTO
if(ENABLE_LTO AND CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

# Include directories
include_directories(${CMAKE_SOURCE_DIR}/include)

# Add subdirectories
add_subdirectory(src)

if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(BUILD_BENCHMARKS)
    add_subdirectory(benchmarks)
endif()

if(BUILD_EXAMPLES)
    add_subdirectory(examples)
endif()

if(BUILD_DOCS)
    add_subdirectory(docs)
endif()

# Installation
install(TARGETS neuraforge neuraforge_core
    EXPORT NeuraForgeTargets
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

install(DIRECTORY include/neuraforge
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    FILES_MATCHING PATTERN "*.hpp" PATTERN "*.h"
)

# Export configuration
configure_package_config_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/NeuraForgeConfig.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/NeuraForgeConfig.cmake"
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/NeuraForge
)

write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/NeuraForgeConfigVersion.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/NeuraForgeConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/NeuraForgeConfigVersion.cmake"
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/NeuraForge
)

install(EXPORT NeuraForgeTargets
    FILE NeuraForgeTargets.cmake
    NAMESPACE NeuraForge::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/NeuraForge
)

# Packaging
set(CPACK_PACKAGE_NAME "NeuraForge")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY ${PROJECT_DESCRIPTION})
set(CPACK_PACKAGE_VENDOR "NeuraForge Team")
set(CPACK_PACKAGE_CONTACT "team@neuraforge.ai")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_SOURCE_DIR}/LICENSE")
set(CPACK_RESOURCE_FILE_README "${CMAKE_SOURCE_DIR}/README.md")

include(CPack)

# Print configuration summary
message(STATUS "")
message(STATUS "NeuraForge Configuration Summary:")
message(STATUS "  Version: ${PROJECT_VERSION}")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  Install Prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "")
message(STATUS "Options:")
message(STATUS "  BUILD_TESTS: ${BUILD_TESTS}")
message(STATUS "  BUILD_BENCHMARKS: ${BUILD_BENCHMARKS}")
message(STATUS "  BUILD_EXAMPLES: ${BUILD_EXAMPLES}")
message(STATUS "  ENABLE_SANITIZERS: ${ENABLE_SANITIZERS}")
message(STATUS "  ENABLE_COVERAGE: ${ENABLE_COVERAGE}")
message(STATUS "  ENABLE_LTO: ${ENABLE_LTO}")
message(STATUS "  ENABLE_CUDA: ${ENABLE_CUDA}")
message(STATUS "")