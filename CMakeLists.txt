cmake_minimum_required(VERSION 3.20)
project(InferenceEngine)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Build type
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_CXX_FLAGS "-Wall -Wextra")
set(CMAKE_CXX_FLAGS_DEBUG "-g")
set(CMAKE_CXX_FLAGS_RELEASE "-O3")

# Find required packages
find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)

# LibTorch
find_package(Torch REQUIRED)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${TORCH_CXX_FLAGS}")

# OpenMP for parallelization
find_package(OpenMP)

if(OpenMP_CXX_FOUND)
  target_link_libraries(inference_engine PUBLIC OpenMP::OpenMP_CXX)
endif()

# JSON library (header-only)
include(FetchContent)
FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.11.3
)
FetchContent_MakeAvailable(nlohmann_json)

# HTTP server library
FetchContent_Declare(
  crow
  GIT_REPOSITORY https://github.com/CrowCpp/Crow.git
  GIT_TAG v1.0+5
)
FetchContent_MakeAvailable(crow)

# Logging library
FetchContent_Declare(
  spdlog
  GIT_REPOSITORY https://github.com/gabime/spdlog.git
  GIT_TAG v1.12.0
)
FetchContent_MakeAvailable(spdlog)

# CLI argument parsing
FetchContent_Declare(
  cxxopts
  GIT_REPOSITORY https://github.com/jarro2783/cxxopts.git
  GIT_TAG v3.1.1
)
FetchContent_MakeAvailable(cxxopts)

# Include directories
include_directories(${CMAKE_SOURCE_DIR}/include)
file(GLOB_RECURSE SOURCES
  "src/*.cpp"
  "src/*.cc"
)

add_executable(inference_engine ${SOURCES})
target_link_libraries(inference_engine
  ${TORCH_LIBRARIES}
  nlohmann_json::nlohmann_json
  Crow::Crow
  spdlog::spdlog
  cxxopts::cxxopts
  Threads::Threads
)

# Copy models directory to build directory
file(COPY ${CMAKE_SOURCE_DIR}/models DESTINATION ${CMAKE_BINARY_DIR})
file(COPY ${CMAKE_SOURCE_DIR}/config DESTINATION ${CMAKE_BINARY_DIR})

# Install target
install(TARGETS inference_engine DESTINATION bin)
install(DIRECTORY models/ DESTINATION share/inference_engine/models)
install(DIRECTORY config/ DESTINATION share/inference_engine/config)