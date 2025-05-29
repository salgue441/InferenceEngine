#!/bin/bash

# Enhanced dependency installation script with robust error handling
# Usage: ./install_dependencies.sh [--skip-docker] [--skip-models] [--force] [--help]

set -euo pipefail # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Secure Internal Field Separator

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_ROOT}/install.log"
LIBTORCH_VERSION="2.1.0"
SKIP_DOCKER=false
SKIP_MODELS=false
FORCE_INSTALL=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

warn() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    error "Installation failed with exit code $exit_code"
    error "Check the log file at: $LOG_FILE"
    error "You can re-run with --force to retry failed operations"
  fi
  exit $exit_code
}

trap cleanup EXIT

# Help function
show_help() {
  cat <<EOF
Inference Engine Dependency Installer

Usage: $0 [OPTIONS]

OPTIONS:
    --skip-docker      Skip Docker installation
    --skip-models      Skip downloading sample models
    --force           Force reinstallation of existing components
    --help            Show this help message

EXAMPLES:
    $0                     # Full installation
    $0 --skip-docker       # Install without Docker
    $0 --force             # Force reinstall everything

The script will:
1. Detect your operating system
2. Install system dependencies
3. Download and install LibTorch
4. Optionally install Docker and Docker Compose
5. Create project directories
6. Download sample models (optional)
7. Create helper scripts

EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --skip-docker)
      SKIP_DOCKER=true
      shift
      ;;
    --skip-models)
      SKIP_MODELS=true
      shift
      ;;
    --force)
      FORCE_INSTALL=true
      shift
      ;;
    --help | -h)
      show_help
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      show_help
      exit 1
      ;;
    esac
  done
}

# System detection with validation
detect_system() {
  log "🔍 Detecting system information..."

  # Detect OS
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    # Detect Linux distribution
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      DISTRO="$ID"
      VERSION="$VERSION_ID"
    elif command -v lsb_release >/dev/null 2>&1; then
      DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
      VERSION=$(lsb_release -sr)
    else
      warn "Cannot detect Linux distribution"
      DISTRO="unknown"
      VERSION="unknown"
    fi
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    DISTRO="macos"
    VERSION=$(sw_vers -productVersion)
  else
    error "Unsupported OS: $OSTYPE"
    error "This script supports Linux and macOS only"
    exit 1
  fi

  # Detect architecture
  ARCH=$(uname -m)

  # Detect available CPU cores
  if command -v nproc >/dev/null 2>&1; then
    CPU_CORES=$(nproc)
  elif command -v sysctl >/dev/null 2>&1; then
    CPU_CORES=$(sysctl -n hw.ncpu)
  else
    CPU_CORES=4
    warn "Cannot detect CPU cores, defaulting to 4"
  fi

  log "✅ System detected:"
  log "   OS: $OS ($DISTRO $VERSION)"
  log "   Architecture: $ARCH"
  log "   CPU Cores: $CPU_CORES"

  # Validate system requirements
  validate_system_requirements
}

# Validate system requirements
validate_system_requirements() {
  log "🔍 Validating system requirements..."

  local requirements_met=true

  # Check available disk space (need at least 5GB)
  local available_space
  if command -v df >/dev/null 2>&1; then
    available_space=$(df /tmp | awk 'NR==2 {print $4}')
    local space_gb=$((available_space / 1024 / 1024))
    if [[ $space_gb -lt 5 ]]; then
      error "Insufficient disk space. Need at least 5GB, have ${space_gb}GB"
      requirements_met=false
    else
      log "✅ Disk space: ${space_gb}GB available"
    fi
  fi

  # Check internet connectivity
  if ! ping -c 1 google.com >/dev/null 2>&1; then
    error "No internet connectivity detected"
    requirements_met=false
  else
    log "✅ Internet connectivity verified"
  fi

  # Check if running as root (discouraged)
  if [[ $EUID -eq 0 ]] && [[ "$FORCE_INSTALL" != true ]]; then
    error "Running as root is not recommended"
    error "Use --force to override this check"
    requirements_met=false
  fi

  if [[ "$requirements_met" != true ]]; then
    error "System requirements not met"
    exit 1
  fi
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if package is installed (Linux)
package_installed() {
  case "$DISTRO" in
  ubuntu | debian)
    dpkg -l "$1" >/dev/null 2>&1
    ;;
  centos | rhel | fedora)
    rpm -q "$1" >/dev/null 2>&1
    ;;
  arch)
    pacman -Q "$1" >/dev/null 2>&1
    ;;
  *)
    return 1
    ;;
  esac
}

# Retry function for network operations
retry() {
  local max_attempts=$1
  local delay=$2
  local command=("${@:3}")
  local attempt=1

  while [[ $attempt -le $max_attempts ]]; do
    if "${command[@]}"; then
      return 0
    else
      if [[ $attempt -eq $max_attempts ]]; then
        error "Command failed after $max_attempts attempts: ${command[*]}"
        return 1
      fi
      warn "Attempt $attempt failed, retrying in ${delay}s..."
      sleep "$delay"
      ((attempt++))
    fi
  done
}

# Install system packages for Ubuntu/Debian
install_ubuntu_packages() {
  log "📦 Installing system packages for Ubuntu/Debian..."

  # Update package list
  if ! retry 3 5 sudo apt-get update; then
    error "Failed to update package list"
    return 1
  fi

  local packages=(
    build-essential
    cmake
    git
    pkg-config
    wget
    curl
    unzip
    libomp-dev
    libssl-dev
    ca-certificates
    python3
    python3-pip
    software-properties-common
    apt-transport-https
    gnupg
    lsb-release
  )

  # Check which packages are missing
  local missing_packages=()
  for package in "${packages[@]}"; do
    if ! package_installed "$package" || [[ "$FORCE_INSTALL" == true ]]; then
      missing_packages+=("$package")
    fi
  done

  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    log "Installing packages: ${missing_packages[*]}"
    if ! retry 3 10 sudo apt-get install -y "${missing_packages[@]}"; then
      error "Failed to install packages: ${missing_packages[*]}"
      return 1
    fi
  else
    log "✅ All required packages already installed"
  fi

  log "✅ Ubuntu/Debian packages installed successfully"
}

# Install system packages for CentOS/RHEL/Fedora
install_rhel_packages() {
  log "📦 Installing system packages for RHEL/CentOS/Fedora..."

  local package_manager
  if command_exists dnf; then
    package_manager="dnf"
  elif command_exists yum; then
    package_manager="yum"
  else
    error "No supported package manager found (dnf/yum)"
    return 1
  fi

  local packages=(
    gcc
    gcc-c++
    cmake
    git
    pkg-config
    wget
    curl
    unzip
    libomp-devel
    openssl-devel
    ca-certificates
    python3
    python3-pip
  )

  log "Using package manager: $package_manager"
  if ! retry 3 10 sudo "$package_manager" install -y "${packages[@]}"; then
    error "Failed to install packages"
    return 1
  fi

  log "✅ RHEL/CentOS/Fedora packages installed successfully"
}

# Install system packages for macOS
install_macos_packages() {
  log "📦 Installing system packages for macOS..."

  # Check if Homebrew is installed
  if ! command_exists brew; then
    log "🍺 Installing Homebrew..."
    if ! retry 3 30 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      error "Failed to install Homebrew"
      return 1
    fi

    # Add Homebrew to PATH for current session
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    log "✅ Homebrew already installed"
  fi

  # Update Homebrew
  if ! retry 3 30 brew update; then
    warn "Failed to update Homebrew, continuing anyway"
  fi

  local packages=(
    cmake
    git
    pkg-config
    wget
    curl
    libomp
    openssl
    python3
  )

  # Install packages
  for package in "${packages[@]}"; do
    if ! brew list "$package" >/dev/null 2>&1 || [[ "$FORCE_INSTALL" == true ]]; then
      log "Installing $package..."
      if ! retry 3 30 brew install "$package"; then
        error "Failed to install $package"
        return 1
      fi
    else
      log "✅ $package already installed"
    fi
  done

  log "✅ macOS packages installed successfully"
}

# Install system dependencies based on OS
install_system_dependencies() {
  log "🔧 Installing system dependencies..."

  case "$OS" in
  linux)
    case "$DISTRO" in
    ubuntu | debian)
      install_ubuntu_packages
      ;;
    centos | rhel | fedora)
      install_rhel_packages
      ;;
    *)
      error "Unsupported Linux distribution: $DISTRO"
      error "Supported distributions: Ubuntu, Debian, CentOS, RHEL, Fedora"
      return 1
      ;;
    esac
    ;;
  macos)
    install_macos_packages
    ;;
  *)
    error "Unsupported operating system: $OS"
    return 1
    ;;
  esac
}

# Create project directories with proper permissions
create_project_structure() {
  log "📁 Creating project directory structure..."

  local directories=(
    "models"
    "logs"
    "config"
    "build"
    "src"
    "include"
    "tests"
    "scripts"
    "monitoring"
    "k8s"
  )

  cd "$PROJECT_ROOT" || {
    error "Cannot access project root: $PROJECT_ROOT"
    return 1
  }

  for dir in "${directories[@]}"; do
    if [[ ! -d "$dir" ]]; then
      if mkdir -p "$dir"; then
        log "✅ Created directory: $dir"
      else
        error "Failed to create directory: $dir"
        return 1
      fi
    else
      log "✅ Directory already exists: $dir"
    fi
  done

  # Set proper permissions
  chmod 755 "${directories[@]}" 2>/dev/null || warn "Could not set directory permissions"

  log "✅ Project structure created successfully"
}

# Download and install LibTorch
install_libtorch() {
  log "🔥 Installing LibTorch..."

  local libtorch_dir="/opt/libtorch"

  # Check if already installed
  if [[ -d "$libtorch_dir" ]] && [[ "$FORCE_INSTALL" != true ]]; then
    log "✅ LibTorch already installed at $libtorch_dir"
    return 0
  fi

  # Determine download URL based on OS and architecture
  local libtorch_url
  local libtorch_file

  case "$OS" in
  linux)
    if [[ "$ARCH" == "x86_64" ]]; then
      libtorch_url="https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-${LIBTORCH_VERSION}%2Bcpu.zip"
      libtorch_file="libtorch-linux-x86_64.zip"
    else
      error "Unsupported Linux architecture: $ARCH"
      error "Only x86_64 is supported for LibTorch"
      return 1
    fi
    ;;
  macos)
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "arm64" ]]; then
      libtorch_url="https://download.pytorch.org/libtorch/cpu/libtorch-macos-${LIBTORCH_VERSION}.zip"
      libtorch_file="libtorch-macos.zip"
    else
      error "Unsupported macOS architecture: $ARCH"
      return 1
    fi
    ;;
  *)
    error "Unsupported OS for LibTorch: $OS"
    return 1
    ;;
  esac

  # Create temporary directory
  local temp_dir
  temp_dir=$(mktemp -d) || {
    error "Failed to create temporary directory"
    return 1
  }

  # Cleanup function for temp directory
  cleanup_temp() {
    [[ -n "$temp_dir" ]] && rm -rf "$temp_dir"
  }
  trap cleanup_temp RETURN

  cd "$temp_dir" || {
    error "Cannot access temporary directory: $temp_dir"
    return 1
  }

  # Download LibTorch
  log "📥 Downloading LibTorch from: $libtorch_url"
  if ! retry 3 30 wget -O "$libtorch_file" "$libtorch_url" --progress=bar:force 2>&1; then
    error "Failed to download LibTorch"
    return 1
  fi

  # Verify download
  if [[ ! -f "$libtorch_file" ]] || [[ ! -s "$libtorch_file" ]]; then
    error "Downloaded file is missing or empty: $libtorch_file"
    return 1
  fi

  local file_size
  file_size=$(stat -c%s "$libtorch_file" 2>/dev/null || stat -f%z "$libtorch_file" 2>/dev/null || echo "unknown")
  log "✅ Downloaded LibTorch (${file_size} bytes)"

  # Extract LibTorch
  log "📦 Extracting LibTorch..."
  if ! unzip -q "$libtorch_file"; then
    error "Failed to extract LibTorch archive"
    return 1
  fi

  # Verify extraction
  if [[ ! -d "libtorch" ]]; then
    error "LibTorch directory not found after extraction"
    return 1
  fi

  # Install LibTorch
  log "📦 Installing LibTorch to $libtorch_dir..."
  if [[ "$FORCE_INSTALL" == true ]] && [[ -d "$libtorch_dir" ]]; then
    sudo rm -rf "$libtorch_dir"
  fi

  sudo mkdir -p /opt || {
    error "Failed to create /opt directory"
    return 1
  }

  if ! sudo mv libtorch "$libtorch_dir"; then
    error "Failed to move LibTorch to $libtorch_dir"
    return 1
  fi

  # Set up environment variables
  setup_libtorch_environment "$libtorch_dir"

  log "✅ LibTorch installed successfully to $libtorch_dir"
}

# Set up LibTorch environment variables
setup_libtorch_environment() {
  local libtorch_dir="$1"

  log "🔗 Setting up LibTorch environment variables..."

  # Create environment setup script
  local env_script="$PROJECT_ROOT/scripts/setup_env.sh"
  cat >"$env_script" <<EOF
#!/bin/bash
# LibTorch environment setup
export CMAKE_PREFIX_PATH="$libtorch_dir:\$CMAKE_PREFIX_PATH"
export LD_LIBRARY_PATH="$libtorch_dir/lib:\$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$libtorch_dir/lib/pkgconfig:\$PKG_CONFIG_PATH"

# For macOS
export DYLD_LIBRARY_PATH="$libtorch_dir/lib:\$DYLD_LIBRARY_PATH"

echo "✅ LibTorch environment loaded"
EOF

  chmod +x "$env_script"

  # Add to shell profiles if they exist
  local profiles=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.zshrc"
    "$HOME/.profile"
  )

  local env_line="source $env_script"

  for profile in "${profiles[@]}"; do
    if [[ -f "$profile" ]] && ! grep -q "$env_script" "$profile"; then
      if echo "$env_line" >>"$profile"; then
        log "✅ Added LibTorch environment to: $profile"
      else
        warn "Failed to add LibTorch environment to: $profile"
      fi
    fi
  done

  # Source for current session
  # shellcheck source=/dev/null
  source "$env_script"

  log "✅ LibTorch environment configured"
}

# Install Docker
install_docker() {
  if [[ "$SKIP_DOCKER" == true ]]; then
    log "⏭️  Skipping Docker installation"
    return 0
  fi

  log "🐳 Installing Docker..."

  if command_exists docker && [[ "$FORCE_INSTALL" != true ]]; then
    log "✅ Docker already installed"
    docker --version | head -1
    return 0
  fi

  case "$OS" in
  linux)
    install_docker_linux
    ;;
  macos)
    install_docker_macos
    ;;
  *)
    error "Docker installation not supported for OS: $OS"
    return 1
    ;;
  esac
}

# Install Docker on Linux
install_docker_linux() {
  log "🐳 Installing Docker on Linux..."

  # Remove old versions
  sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

  # Add Docker's official GPG key
  if ! retry 3 10 curl -fsSL https://download.docker.com/linux/"$DISTRO"/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
    error "Failed to add Docker GPG key"
    return 1
  fi

  # Add Docker repository
  local docker_repo="deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable"
  if ! echo "$docker_repo" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null; then
    error "Failed to add Docker repository"
    return 1
  fi

  # Update package list and install Docker
  if ! retry 3 10 sudo apt-get update; then
    error "Failed to update package list for Docker"
    return 1
  fi

  if ! retry 3 30 sudo apt-get install -y docker-ce docker-ce-cli containerd.io; then
    error "Failed to install Docker"
    return 1
  fi

  # Add user to docker group
  if ! sudo usermod -aG docker "$USER"; then
    warn "Failed to add user to docker group"
  else
    log "✅ Added $USER to docker group"
    log "⚠️  Please logout and login again to use Docker without sudo"
  fi

  # Start and enable Docker service
  if command_exists systemctl; then
    sudo systemctl start docker || warn "Failed to start Docker service"
    sudo systemctl enable docker || warn "Failed to enable Docker service"
  fi

  log "✅ Docker installed successfully"
}

# Install Docker on macOS
install_docker_macos() {
  log "🐳 Docker installation on macOS..."

  if command_exists docker; then
    log "✅ Docker already installed"
    return 0
  fi

  log "🍎 Please install Docker Desktop manually from:"
  log "   https://www.docker.com/products/docker-desktop"
  log ""
  log "After installation, start Docker Desktop and return to continue"

  if [[ "$FORCE_INSTALL" != true ]]; then
    read -r -p "Press Enter when Docker Desktop is installed and running..."

    # Verify Docker is working
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
      if docker --version >/dev/null 2>&1; then
        log "✅ Docker verified and working"
        return 0
      fi
      sleep 2
      ((attempts++))
    done

    warn "Docker verification failed, but continuing anyway"
  fi
}

# Install Docker Compose
install_docker_compose() {
  if [[ "$SKIP_DOCKER" == true ]]; then
    return 0
  fi

  log "📦 Installing Docker Compose..."

  if command_exists docker-compose && [[ "$FORCE_INSTALL" != true ]]; then
    log "✅ Docker Compose already installed"
    docker-compose --version
    return 0
  fi

  case "$OS" in
  linux)
    # Get latest version
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ -z "$compose_version" ]]; then
      warn "Could not determine latest Docker Compose version, using fallback"
      compose_version="2.20.0"
    fi

    local compose_url="https://github.com/docker/compose/releases/download/v${compose_version}/docker-compose-linux-$ARCH"

    if ! retry 3 30 sudo curl -L "$compose_url" -o /usr/local/bin/docker-compose; then
      error "Failed to download Docker Compose"
      return 1
    fi

    sudo chmod +x /usr/local/bin/docker-compose
    log "✅ Docker Compose v$compose_version installed"
    ;;
  macos)
    if command_exists brew; then
      if ! retry 3 30 brew install docker-compose; then
        error "Failed to install Docker Compose via Homebrew"
        return 1
      fi
      log "✅ Docker Compose installed via Homebrew"
    else
      warn "Docker Compose should be included with Docker Desktop on macOS"
    fi
    ;;
  esac
}

# Download sample models
download_sample_models() {
  if [[ "$SKIP_MODELS" == true ]]; then
    log "⏭️  Skipping model download"
    return 0
  fi

  log "📥 Downloading sample models..."

  # Check if Python and PyTorch are available
  if ! command_exists python3; then
    warn "Python3 not available, skipping model download"
    return 0
  fi

  # Install PyTorch if not available
  if ! python3 -c "import torch" 2>/dev/null; then
    log "📦 Installing PyTorch for model creation..."
    if ! retry 3 60 python3 -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu; then
      warn "Failed to install PyTorch, skipping model download"
      return 0
    fi
  fi

  cd "$PROJECT_ROOT/models" || {
    error "Cannot access models directory"
    return 1
  }

  # Create sample ResNet50 model
  log "🔥 Creating ResNet50 model..."
  cat >create_model.py <<'EOF'
import torch
import torchvision.models as models
import sys
import os

try:
    print("Creating ResNet50 model...")
    
    # Create and save a ResNet50 model
    model = models.resnet50(weights='IMAGENET1K_V1')
    model.eval()
    
    # Trace the model for inference
    example_input = torch.rand(1, 3, 224, 224)
    traced_model = torch.jit.trace(model, example_input)
    
    # Save the model
    model_path = 'resnet50.pt'
    traced_model.save(model_path)
    
    # Verify the saved model
    if os.path.exists(model_path) and os.path.getsize(model_path) > 0:
        print(f"✅ ResNet50 model saved successfully: {model_path}")
        print(f"   Model size: {os.path.getsize(model_path) / (1024*1024):.1f} MB")
        
        # Test loading
        loaded_model = torch.jit.load(model_path)
        test_output = loaded_model(example_input)
        print(f"   Test inference output shape: {test_output.shape}")
        print("✅ Model verification passed")
    else:
        print("❌ Failed to save model")
        sys.exit(1)
        
except Exception as e:
    print(f"❌ Error creating model: {e}")
    sys.exit(1)
EOF

  if python3 create_model.py; then
    rm create_model.py
    log "✅ Sample models downloaded successfully"
  else
    warn "Failed to create sample models, but continuing installation"
    rm -f create_model.py
  fi

  cd "$PROJECT_ROOT" || return 1
}

# Create helper scripts
create_helper_scripts() {
  log "📝 Creating helper scripts..."

  # Create build script
  cat >"$PROJECT_ROOT/build.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_TYPE="${1:-Release}"
JOBS="${2:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

echo "🔨 Building Inference Engine..."
echo "   Build Type: $BUILD_TYPE"
echo "   Parallel Jobs: $JOBS"

# Source LibTorch environment
if [[ -f "$SCRIPT_DIR/scripts/setup_env.sh" ]]; then
    source "$SCRIPT_DIR/scripts/setup_env.sh"
else
    echo "⚠️  LibTorch environment script not found"
    export CMAKE_PREFIX_PATH="/opt/libtorch:$CMAKE_PREFIX_PATH"
    export LD_LIBRARY_PATH="/opt/libtorch/lib:$LD_LIBRARY_PATH"
fi

# Create and enter build directory
mkdir -p "$SCRIPT_DIR/build"
cd "$SCRIPT_DIR/build"

# Configure and build
echo "🔧 Configuring CMake..."
cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" ..

echo "🔨 Building with $JOBS parallel jobs..."
make -j"$JOBS"

echo ""
echo "✅ Build complete!"
echo "📍 Binary location: $SCRIPT_DIR/build/inference_engine"
echo "🚀 Run with: ./run.sh"
EOF

  # Create run script
  cat >"$PROJECT_ROOT/run.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source LibTorch environment
if [[ -f "$SCRIPT_DIR/scripts/setup_env.sh" ]]; then
    source "$SCRIPT_DIR/scripts/setup_env.sh"
else
    echo "⚠️  LibTorch environment script not found"
    export LD_LIBRARY_PATH="/opt/libtorch/lib:$LD_LIBRARY_PATH"
fi

# Check if binary exists
BINARY="$SCRIPT_DIR/build/inference_engine"
if [[ ! -f "$BINARY" ]]; then
    echo "❌ Binary not found: $BINARY"
    echo "💡 Please run ./build.sh first"
    exit 1
fi

echo "🚀 Starting Inference Engine..."
echo "📍 Config: $SCRIPT_DIR/config/server.json"
echo "📊 Health check: http://localhost:8080/health"
echo ""

# Run the inference engine
exec "$BINARY" --config "$SCRIPT_DIR/config/server.json" "$@"
EOF

  # Create development script
  cat >"$PROJECT_ROOT/dev.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Starting development environment..."

# Build in debug mode
if ! "$SCRIPT_DIR/build.sh" Debug; then
    echo "❌ Debug build failed"
    exit 1
fi

# Start with hot reload using entr if available
if command -v entr >/dev/null 2>&1; then
    echo "🔄 Hot reload enabled (using entr)"
    echo "   Watching src/ and include/ directories"
    echo "   Press Ctrl+C to stop"
    
    find "$SCRIPT_DIR/src" "$SCRIPT_DIR/include" -name "*.cpp" -o -name "*.hpp" -o -name "*.h" | \
        entr -r "$SCRIPT_DIR/run.sh" --debug
else
    echo "💡 Install 'entr' for hot reload functionality"
    echo "🚀 Starting in debug mode..."
    "$SCRIPT_DIR/run.sh" --debug
fi
EOF

  # Create test script
  cat >"$PROJECT_ROOT/test.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Running tests..."

# Build tests
if ! "$SCRIPT_DIR/build.sh" Debug; then
    echo "❌ Test build failed"
    exit 1
fi

# Source environment
if [[ -f "$SCRIPT_DIR/scripts/setup_env.sh" ]]; then
    source "$SCRIPT_DIR/scripts/setup_env.sh"
fi

# Run tests with CTest
cd "$SCRIPT_DIR/build"
if [[ -f "Makefile" ]] && make help | grep -q test; then
    echo "🏃 Running unit tests..."
    make test
else
    echo "⚠️  No tests configured yet"
    echo "💡 Add tests to your CMakeLists.txt"
fi

echo "✅ Test run complete!"
EOF

  # Make scripts executable
  chmod +x "$PROJECT_ROOT"/{build,run,dev,test}.sh

  log "✅ Helper scripts created:"
  log "   ./build.sh  - Build the project"
  log "   ./run.sh    - Run the server"
  log "   ./dev.sh    - Development mode with hot reload"
  log "   ./test.sh   - Run tests"
}

# Verify installation
verify_installation() {
  log "🔍 Verifying installation..."

  local verification_failed=false

  # Check system tools
  local required_commands=(cmake git wget curl)
  for cmd in "${required_commands[@]}"; do
    if command_exists "$cmd"; then
      log "✅ $cmd: $(command -v "$cmd")"
    else
      error "❌ $cmd: not found"
      verification_failed=true
    fi
  done

  # Check LibTorch
  if [[ -d "/opt/libtorch" ]]; then
    log "✅ LibTorch: /opt/libtorch"
    if [[ -f "/opt/libtorch/lib/libtorch.so" ]] || [[ -f "/opt/libtorch/lib/libtorch.dylib" ]]; then
      log "✅ LibTorch libraries: found"
    else
      warn "⚠️  LibTorch libraries: questionable"
    fi
  else
    error "❌ LibTorch: not found"
    verification_failed=true
  fi

  # Check Docker (if not skipped)
  if [[ "$SKIP_DOCKER" != true ]]; then
    if command_exists docker; then
      log "✅ Docker: $(docker --version)"
      if command_exists docker-compose; then
        log "✅ Docker Compose: $(docker-compose --version)"
      else
        warn "⚠️  Docker Compose: not found"
      fi
    else
      warn "⚠️  Docker: not found"
    fi
  fi

  # Check project structure
  local required_dirs=(models logs config build)
  for dir in "${required_dirs[@]}"; do
    if [[ -d "$PROJECT_ROOT/$dir" ]]; then
      log "✅ Directory: $dir"
    else
      error "❌ Directory missing: $dir"
      verification_failed=true
    fi
  done

  # Check helper scripts
  local scripts=(build.sh run.sh dev.sh test.sh)
  for script in "${scripts[@]}"; do
    if [[ -x "$PROJECT_ROOT/$script" ]]; then
      log "✅ Script: $script"
    else
      warn "⚠️  Script missing or not executable: $script"
    fi
  done

  if [[ "$verification_failed" == true ]]; then
    error "❌ Installation verification failed"
    error "💡 Try running with --force to fix issues"
    return 1
  else
    log "✅ Installation verification successful"
    return 0
  fi
}

# Print final summary and next steps
print_summary() {
  log ""
  log "🎉 Installation Complete!"
  log "========================"
  log ""
  log "📋 What was installed:"
  log "   ✅ System dependencies ($OS $DISTRO)"
  log "   ✅ LibTorch ${LIBTORCH_VERSION}"
  log "   ✅ Project structure"
  log "   ✅ Helper scripts"

  if [[ "$SKIP_DOCKER" != true ]]; then
    log "   ✅ Docker and Docker Compose"
  fi

  if [[ "$SKIP_MODELS" != true ]]; then
    log "   ✅ Sample models"
  fi

  log ""
  log "🚀 Next steps:"
  log "   1. Build the project:      ./build.sh"
  log "   2. Run the server:         ./run.sh"
  log "   3. Development mode:       ./dev.sh"
  log "   4. Run tests:              ./test.sh"
  log "   5. Docker development:     docker-compose --profile dev up"
  log ""
  log "🌐 Endpoints (when running):"
  log "   • Server:                  http://localhost:8080"
  log "   • Health check:            http://localhost:8080/health"
  log "   • Metrics:                 http://localhost:9090/metrics"
  log ""
  log "📚 Documentation:"
  log "   • Configuration:           config/server.json"
  log "   • Logs:                    logs/inference.log"
  log "   • Build output:            build/"
  log ""

  if [[ "$OS" == "linux" ]] && ! groups | grep -q docker; then
    warn "⚠️  Remember to logout and login to use Docker without sudo"
  fi

  log "📄 Full installation log: $LOG_FILE"
}

# Main execution function
main() {
  # Initialize log file
  echo "Inference Engine Installation Log - $(date)" >"$LOG_FILE"

  log "🚀 Starting Inference Engine Installation"
  log "=========================================="

  # Parse command line arguments
  parse_args "$@"

  # Run installation steps
  detect_system
  install_system_dependencies
  create_project_structure
  install_libtorch
  install_docker
  install_docker_compose
  download_sample_models
  create_helper_scripts
  verify_installation
  print_summary

  log "✅ Installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
