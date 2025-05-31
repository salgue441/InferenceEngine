#!/bin/bash

# NeuraForge Test Script
# Safe testing script with error handling and system protection

set -euo pipefail
IFS=$'\n\t'

# Configuration and constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/build"
readonly TEST_RESULTS_DIR="${PROJECT_ROOT}/test-results"

# Default values
PRESET="debug"
COVERAGE=false
PARALLEL=true
VERBOSE=false
UNIT_TESTS=true
INTEGRATION_TESTS=true
BENCHMARKS=false
OUTPUT_FORMAT="default"
TIMEOUT=300
DRY_RUN=false
FILTER=""

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Utility Functions
log() {
  echo -e "${GREEN}[TEST]${NC} $(date '+%H:%M:%S') $*" >&2
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
    error "Test execution failed with exit code $exit_code"
    info "Check test output above for details"
  fi
  exit $exit_code
}

trap cleanup EXIT INT TERM

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

validate_environment() {
  log "Validating test environment..."

  # Check required commands
  local required_commands=("cmake" "ctest")
  for cmd in "${required_commands[@]}"; do
    if ! command_exists "$cmd"; then
      error "Required command '$cmd' not found"
      return 1
    fi
  done

  # Check if build exists
  local build_path="$BUILD_DIR/$PRESET"
  if [[ ! -d "$build_path" ]]; then
    error "Build directory not found: $build_path"
    info "Please run build script first: ./scripts/build.sh --preset=$PRESET --tests"
    return 1
  fi

  # Check if tests were built
  if [[ ! -f "$build_path/CTestTestfile.cmake" ]]; then
    error "Tests not found in build directory"
    info "Please rebuild with tests enabled: ./scripts/build.sh --preset=$PRESET --tests"
    return 1
  fi

  log "Environment validation completed"
}

setup_test_results() {
  if [[ ! -d "$TEST_RESULTS_DIR" ]]; then
    log "Creating test results directory: $TEST_RESULTS_DIR"

    if [[ "$DRY_RUN" == true ]]; then
      info "DRY RUN: Would create directory $TEST_RESULTS_DIR"
    else
      mkdir -p "$TEST_RESULTS_DIR"
    fi
  fi
}

run_unit_tests() {
  if [[ "$UNIT_TESTS" == true ]]; then
    log "Running unit tests..."
    local ctest_args=(
      "--preset=$PRESET"
      "--output-on-failure"
    )

    if [[ "$PARALLEL" == true ]]; then
      ctest_args+=("--parallel" "$(nproc)")
    fi

    if [[ "$VERBOSE" == true ]]; then
      ctest_args+=("--verbose")
    fi

    ctest_args+=("--timeout" "$TIMEOUT")
    if [[ -n "$FILTER" ]]; then
      ctest_args+=("-R" "$FILTER")
    fi

    case "$OUTPUT_FORMAT" in
    junit)
      ctest_args+=("--output-junit" "$TEST_RESULTS_DIR/unit_tests.xml")
      ;;
    json)
      warn "JSON output not directly supported by CTest, using default format"
      ;;
    esac

    ctest_args+=("-L" "unit")
    if [[ "$DRY_RUN" == true ]]; then
      info "DRY RUN: Would run: ctest ${ctest_args[*]}"
      return 0
    fi

    cd "$PROJECT_ROOT"

    local start_time=$(date +%s)
    local test_result=0

    if ! ctest "${ctest_args[@]}"; then
      test_result=1
      error "Unit tests failed"
    else
      log "Unit tests passed"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    info "Unit tests completed in ${duration}s"

    return $test_result
  fi
}

run_integration_tests() {
  if [[ "$INTEGRATION_TESTS" == true ]]; then
    log "Running integration tests..."
    local ctest_args=(
      "--preset=$PRESET"
      "--output-on-failure"
    )

    if [[ "$PARALLEL" == true ]]; then
      ctest_args+=("--parallel" "$(nproc)")
    fi

    if [[ "$VERBOSE" == true ]]; then
      ctest_args+=("--verbose")
    fi

    ctest_args+=("--timeout" "$TIMEOUT")
    if [[ -n "$FILTER" ]]; then
      ctest_args+=("-R" "$FILTER")
    fi

    case "$OUTPUT_FORMAT" in
    junit)
      ctest_args+=("--output-junit" "$TEST_RESULTS_DIR/integration_tests.xml")
      ;;
    esac

    ctest_args+=("-L" "integration")
    if [[ "$DRY_RUN" == true ]]; then
      info "DRY RUN: Would run: ctest ${ctest_args[*]}"
      return 0
    fi

    cd "$PROJECT_ROOT"

    local start_time=$(date +%s)
    local test_result=0

    if ! ctest "${ctest_args[@]}"; then
      test_result=1
      error "Integration tests failed"
    else
      log "Integration tests passed"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    info "Integration tests completed in ${duration}s"

    return $test_result
  fi
}

run_benchmarks() {
  if [[ "$BENCHMARKS" == true ]]; then
    log "Running benchmarks..."

    local benchmark_binary="$BUILD_DIR/$PRESET/bin/neuraforge_benchmarks"

    if [[ ! -f "$benchmark_binary" ]]; then
      warn "Benchmark binary not found: $benchmark_binary"
      info "Skipping benchmarks (rebuild with --benchmarks to include)"
      return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
      info "DRY RUN: Would run benchmarks from $benchmark_binary"
      return 0
    fi

    local benchmark_args=(
      "--benchmark_format=json"
      "--benchmark_out=$TEST_RESULTS_DIR/benchmarks.json"
    )

    if [[ -n "$FILTER" ]]; then
      benchmark_args+=("--benchmark_filter=$FILTER")
    fi

    local start_time=$(date +%s)

    if ! "$benchmark_binary" "${benchmark_args[@]}"; then
      error "Benchmarks failed"
      return 1
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    info "Benchmarks completed in ${duration}s"

    log "Benchmark results saved to: $TEST_RESULTS_DIR/benchmarks.json"
  fi
}

generate_coverage() {
  if [[ "$COVERAGE" == true ]]; then
    log "Generating coverage report..."

    if ! command_exists "lcov"; then
      warn "lcov not found, skipping coverage report"
      info "Install lcov to generate coverage reports: sudo apt-get install lcov"
      return 0
    fi

    local coverage_dir="$TEST_RESULTS_DIR/coverage"
    local build_path="$BUILD_DIR/$PRESET"

    if [[ "$DRY_RUN" == true ]]; then
      info "DRY RUN: Would generate coverage report in $coverage_dir"
      return 0
    fi

    mkdir -p "$coverage_dir"
    lcov --capture \
      --directory "$build_path" \
      --output-file "$coverage_dir/coverage.info" \
      --quiet

    lcov --remove "$coverage_dir/coverage.info" \
      '/usr/*' \
      '*/vcpkg_installed/*' \
      '*/build/_deps/*' \
      '*/tests/*' \
      --output-file "$coverage_dir/coverage_filtered.info" \
      --quiet

    genhtml "$coverage_dir/coverage_filtered.info" \
      --output-directory "$coverage_dir/html" \
      --title "NeuraForge Coverage Report" \
      --quiet

    log "Coverage report generated: $coverage_dir/html/index.html"
    lcov --summary "$coverage_dir/coverage_filtered.info"
  fi
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

NeuraForge Test Script - Safe test execution with comprehensive error handling

OPTIONS:
    --preset=PRESET         Test preset (debug|release|profile) [default: debug]
    --coverage              Generate coverage report (requires lcov)
    --parallel              Enable parallel test execution [default: true]
    --no-parallel           Disable parallel test execution
    --verbose               Enable verbose test output
    --unit-only             Run only unit tests
    --integration-only      Run only integration tests
    --benchmarks            Include benchmark tests
    --format=FORMAT         Output format (default|junit|json) [default: default]
    --timeout=SECONDS       Test timeout in seconds [default: 300]
    --filter=PATTERN        Run tests matching pattern
    --dry-run               Show what would be done without executing
    --help                  Show this help message

EXAMPLES:
    $0                                      # Run all tests with debug preset
    $0 --preset=release --unit-only         # Run unit tests with release preset
    $0 --coverage --verbose                 # Run tests with coverage and verbose output
    $0 --filter="InferenceEngine*"          # Run tests matching pattern
    $0 --benchmarks --format=junit          # Run with benchmarks, output JUnit XML

ENVIRONMENT:
    TEST_RESULTS_DIR        Override test results directory
    CTEST_PARALLEL_LEVEL    Override parallel test count
    
EOF
}

# Parse Arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --preset=*)
      PRESET="${1#*=}"
      shift
      ;;
    --coverage)
      COVERAGE=true
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
    --verbose)
      VERBOSE=true
      shift
      ;;
    --unit-only)
      UNIT_TESTS=true
      INTEGRATION_TESTS=false
      shift
      ;;
    --integration-only)
      UNIT_TESTS=false
      INTEGRATION_TESTS=true
      shift
      ;;
    --benchmarks)
      BENCHMARKS=true
      shift
      ;;
    --format=*)
      OUTPUT_FORMAT="${1#*=}"
      shift
      ;;
    --timeout=*)
      TIMEOUT="${1#*=}"
      shift
      ;;
    --filter=*)
      FILTER="${1#*=}"
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
  log "Starting NeuraForge test execution"

  parse_arguments "$@"
  case "$PRESET" in
  debug | release | profile) ;;
  *)
    error "Invalid preset: $PRESET"
    info "Valid presets: debug, release, profile"
    exit 1
    ;;
  esac

  # Show configuration
  info "Test configuration:"
  info "  Preset: $PRESET"
  info "  Coverage: $COVERAGE"
  info "  Parallel: $PARALLEL"
  info "  Unit tests: $UNIT_TESTS"
  info "  Integration tests: $INTEGRATION_TESTS"
  info "  Benchmarks: $BENCHMARKS"
  info "  Output format: $OUTPUT_FORMAT"
  info "  Timeout: ${TIMEOUT}s"
  info "  Filter: ${FILTER:-none}"
  info "  Dry run: $DRY_RUN"

  # Setup and validation
  validate_environment
  setup_test_results

  local overall_result=0
  if ! run_unit_tests; then
    overall_result=1
  fi

  if ! run_integration_tests; then
    overall_result=1
  fi

  if ! run_benchmarks; then
    overall_result=1
  fi

  generate_coverage
  if [[ $overall_result -eq 0 ]]; then
    log "All tests completed successfully!"
  else
    error "Some tests failed"
    exit 1
  fi

  if [[ -d "$TEST_RESULTS_DIR" ]]; then
    info "Test results saved to: $TEST_RESULTS_DIR"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
