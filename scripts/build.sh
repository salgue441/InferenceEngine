#!/bin/bash

# NeuraForge Build Script
# Safe build script with error handling

set -euo pipefail
IFS=$'\n\t'

# Configuration and constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/build"
readonly INSTALL_DIR="${PROJECT_ROOT}/install"

# Default values
PRESET="release"
CLEAN=false
PARALLEL=true
VERBOSE=false
TESTS=false
BENCHMARKS=false
INSTALL=false
DRY_RUN=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Utility functions
log() {
  echo -e "${GREEN}[BUILD]${NC} $(date '+%H:%M:%S') $*" >&2
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $*" >&2
}

error() {
  echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2
}

info() {
  echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*" >&2
}

cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    error "Build failed with exit code $exit_code"
    info "Check the error messages above for details"
  fi
  exit $exit_code
}

trap cleanup EXIT INT TERM
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

validate_environment() {
  log "Validating build environment..."

  # Check required commands
  local required_commands=("cmake" "ninja")
  for cmd in "${required_commands[@]}"; do
    if ! command_exists "$cmd"; then
      error "Required command '$cmd' not found"
      info "Please install $cmd before running this script"
      return 1
    fi
  done

  # Check vcpkg
  if [[ -z "${VCPKG_ROOT:-}" ]]; then
    error "VCPKG_ROOT environment variable not set"
    info "Please set VCPKG_ROOT to your vcpkg installation directory"
    return 1
  fi

  if [[ ! -f "${VCPKG_ROOT}/vcpkg" ]] && [[ ! -f "${VCPKG_ROOT}/vcpkg.exe" ]]; then
    error "vcpkg executable not found in VCPKG_ROOT: ${VCPKG_ROOT}"
    return 1
  fi

  # Check project files
  if [[ ! -f "${PROJECT_ROOT}/CMakeLists.txt" ]]; then
    error "CMakeLists.txt not found in project root: ${PROJECT_ROOT}"
    return 1
  fi

  if [[ ! -f "${PROJECT_ROOT}/vcpkg.json" ]]; then
    error "vcpkg.json not found in project root: ${PROJECT_ROOT}"
    return 1
  fi

  # Check CMake presets
  if [[ ! -f "${PROJECT_ROOT}/CMakePresets.json" ]]; then
    warn "CMakePresets.json not found, using default configuration"
  fi

  log "Environment validation completed successfully"
}

validate_preset() {
  local preset="$1"
  case "$preset" in
  debug | release | release-linux | profile | cuda)
    return 0
    ;;
  *)
    error "Invalid preset: $preset"
    info "Valid presets: debug, release, release-linux, profile, cuda"
    return 1
    ;;
  esac
}

clean_build() {
  if [[ "$CLEAN" == true ]]; then
    log "Cleaning build directory..."

    if [[ -d "$BUILD_DIR" ]]; then
      if [[ "$BUILD_DIR" == "/" ]] || [[ "$BUILD_DIR" == "/usr" ]] || [[ "$BUILD_DIR" == "/home" ]]; then
        error "Refusing to delete system directory: $BUILD_DIR"
        return 1
      fi

      if [[ "$DRY_RUN" == true ]]; then
        info "DRY RUN: Would remove $BUILD_DIR"
      else
        rm -rf "$BUILD_DIR"
        log "Build directory cleaned"
      fi
    else
      info "Build directory does not exist, skipping clean"
    fi
  fi
}

configure_project() {
  log "Configuring project with preset: $PRESET"

  local cmake_args=()
  if [[ -f "${PROJECT_ROOT}/CMakePresets.json" ]]; then
    cmake_args+=("--preset=$PRESET")
  else
    warn "Using fallback configuration (no CMakePresets.json)"
    cmake_args+=(
      "-B" "$BUILD_DIR/$PRESET"
      "-S" "$PROJECT_ROOT"
      "-G" "Ninja"
      "-DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
    )

    case "$PRESET" in
    debug)
      cmake_args+=("-DCMAKE_BUILD_TYPE=Debug")
      cmake_args+=("-DBUILD_TESTS=ON")
      ;;
    release | release-linux)
      cmake_args+=("-DCMAKE_BUILD_TYPE=Release")
      cmake_args+=("-DBUILD_TESTS=OFF")
      ;;
    profile)
      cmake_args+=("-DCMAKE_BUILD_TYPE=RelWithDebInfo")
      ;;
    esac
  fi

  # Override test building if requested
  if [[ "$TESTS" == true ]]; then
    cmake_args+=("-DBUILD_TESTS=ON")
  fi

  if [[ "$BENCHMARKS" == true ]]; then
    cmake_args+=("-DBUILD_BENCHMARKS=ON")
  fi

  if [[ "$VERBOSE" == true ]]; then
    cmake_args+=("--" "-v")
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "DRY RUN: Would run: cmake ${cmake_args[*]}"
    return 0
  fi

  cd "$PROJECT_ROOT"
  if ! cmake "${cmake_args[@]}"; then
    error "CMake configuration failed"
    return 1
  fi

  log "Project configured successfully"
}

build_project() {
  log "Building project..."

  local build_args=()

  if [[ -f "${PROJECT_ROOT}/CMakePresets.json" ]]; then
    build_args+=("--preset=$PRESET")
  else
    build_args+=("--build" "$BUILD_DIR/$PRESET")
  fi

  if [[ "$PARALLEL" == true ]]; then
    build_args+=("--parallel")
  fi

  if [[ "$VERBOSE" == true ]]; then
    build_args+=("--verbose")
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "DRY RUN: Would run: cmake ${build_args[*]}"
    return 0
  fi

  cd "$PROJECT_ROOT"
  if ! cmake "${build_args[@]}"; then
    error "Build failed"
    return 1
  fi

  log "Build completed successfully"
}

install_project() {
  if [[ "$INSTALL" == true ]]; then
    log "Installing project..."

    local install_args=("--install")
    if [[ -f "${PROJECT_ROOT}/CMakePresets.json" ]]; then
      install_args+=("$BUILD_DIR/$PRESET")
    else
      install_args+=("$BUILD_DIR/$PRESET")
    fi

    install_args+=("--prefix" "$INSTALL_DIR/$PRESET")

    if [[ "$DRY_RUN" == true ]]; then
      info "DRY RUN: Would run: cmake ${install_args[*]}"
      return 0
    fi

    cd "$PROJECT_ROOT"
    if ! cmake "${install_args[@]}"; then
      error "Installation failed"
      return 1
    fi

    log "Installation completed successfully"
  fi
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

NeuraForge Build Script - Safe build automation with error handling

OPTIONS:
    --preset=PRESET     Build preset (debug|release|release-linux|profile|cuda) [default: release]
    --clean             Clean build directory before building
    --parallel          Enable parallel build [default: true]
    --no-parallel       Disable parallel build
    --tests             Build and run tests
    --benchmarks        Build benchmarks
    --install           Install after building
    --verbose           Enable verbose output
    --dry-run           Show what would be done without executing
    --help              Show this help message

EXAMPLES:
    $0                                  # Basic release build
    $0 --preset=debug --tests           # Debug build with tests
    $0 --clean --preset=release         # Clean release build
    $0 --dry-run --preset=debug         # Preview debug build commands

ENVIRONMENT:
    VCPKG_ROOT          Path to vcpkg installation (required)
    CMAKE_BUILD_TYPE    Override build type
    
EOF
}

# Argument Parsing
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --preset=*)
      PRESET="${1#*=}"
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    --parallel)
      PARALLEL=true
      shift
      ;;
    --no-parallel)
      PARALLEL=false
      shift
      ;;
    --tests)
      TESTS=true
      shift
      ;;
    --benchmarks)
      BENCHMARKS=true
      shift
      ;;
    --install)
      INSTALL=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
    esac
  done
}

# Main Function
main() {
  log "Starting NeuraForge build process"
  info "Project root: $PROJECT_ROOT"
  info "Script directory: $SCRIPT_DIR"

  parse_arguments "$@"
  validate_preset "$PRESET"

  info "Build configuration:"
  info "  Preset: $PRESET"
  info "  Clean: $CLEAN"
  info "  Parallel: $PARALLEL"
  info "  Tests: $TESTS"
  info "  Benchmarks: $BENCHMARKS"
  info "  Install: $INSTALL"
  info "  Verbose: $VERBOSE"
  info "  Dry run: $DRY_RUN"

  # Validation steps
  validate_environment

  # Build steps
  clean_build
  configure_project
  build_project
  install_project

  log "Build process completed successfully!"
  local build_output="$BUILD_DIR/$PRESET"

  if [[ -d "$build_output" ]]; then
    info "Build artifacts location: $build_output"
    if [[ -d "$build_output/bin" ]]; then
      info "Binaries: $build_output/bin/"
    fi
    if [[ -d "$build_output/lib" ]]; then
      info "Libraries: $build_output/lib/"
    fi
  fi

  if [[ "$INSTALL" == true ]] && [[ -d "$INSTALL_DIR/$PRESET" ]]; then
    info "Installation location: $INSTALL_DIR/$PRESET"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
