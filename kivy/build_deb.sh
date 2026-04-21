#!/bin/bash
#
# build_deb.sh - Build script for img2sketch Debian package
#
# This script orchestrates the complete Debian package build process:
# 1. Install system dependencies
# 2. Create virtual environment with uv
# 3. Build the application with PyInstaller
# 4. Package into .deb using dpkg-deb
#
# Usage: ./build_deb.sh [--install-deps] [--clean] [--help]
#
# Requirements:
#   - Ubuntu 22.04+ or Debian 12+ (bookworm)
#   - sudo privileges for installing dependencies
#   - curl (for uv installation)

set -euo pipefail

# Configuration
APP_NAME="img2sketch"
APP_VERSION="0.5.0"
DEB_SUFFIX="1"
ARCH="amd64"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}"
BUILD_DIR="${SCRIPT_DIR}/debian/build"
DIST_DIR="${SCRIPT_DIR}/dist"
PACKAGE_DIR="${SCRIPT_DIR}/debian/${APP_NAME}"
DEB_OUTPUT_DIR="${SCRIPT_DIR}"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_warn "Running as root. This is okay for building but not recommended."
    fi
}

# Print usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build img2sketch Debian package from source.

Options:
    --install-deps    Install system dependencies (requires sudo)
    --clean          Clean build artifacts before building
    --help           Show this help message

Examples:
    $(basename "$0") --install-deps   # Install deps and build
    $(basename "$0") --clean          # Clean and build

EOF
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."

    # Check if apt-get is available
    if ! command -v apt-get >/dev/null 2>&1; then
        log_error "apt-get not found. This script requires Debian/Ubuntu."
        exit 1
    fi

    # Update package lists
    log_info "Updating package lists..."
    sudo apt-get update -qq

    # Install build dependencies
    log_info "Installing build dependencies..."
    DEPS=(
        # Build tools
        build-essential
        dpkg-dev
        debhelper
        # Python development
        python3
        python3-pip
        python3-venv
        python3-dev
        # SSL/FFI
        libffi-dev
        libssl-dev
        # SDL2 libraries for Kivy
        libsdl2-dev
        libsdl2-image-dev
        libsdl2-mixer-dev
        libsdl2-ttf-dev
        libportmidi-dev
        # FFmpeg/AV libraries for video
        libswscale-dev
        libavformat-dev
        libavcodec-dev
        libavdevice-dev
        # Compression
        zlib1g-dev
        # OpenCV
        libopencv-dev
        # Utilities
        ffmpeg
        curl
        wget
    )

    sudo apt-get install -y --no-install-recommends "${DEPS[@]}"

    log_success "System dependencies installed successfully."
}

# Install uv (if not available)
install_uv() {
    log_info "Checking for uv..."

    if command -v uv >/dev/null 2>&1; then
        log_info "uv already installed: $(uv --version)"
    else
        log_info "Installing uv..."
        # Install uv using the official installer
        curl -LsSf https://astral.sh/uv/install.sh | sh

        # Add uv to PATH if installed in user directory
        if [ -f "${HOME}/.local/bin/uv" ]; then
            export PATH="${HOME}/.local/bin:${PATH}"
            log_info "uv installed to ${HOME}/.local/bin"
        fi

        log_success "uv installed successfully."
    fi
}

# Install uv (if not available) - alternative method for CI
install_uv_alternative() {
    log_info "Checking for uv (alternative method)..."

    if command -v uv >/dev/null 2>&1; then
        log_info "uv already installed: $(uv --version)"
        return 0
    fi

    log_info "Installing uv using pip..."
    python3 -m pip install --user uv

    # Add to PATH
    export PATH="${HOME}/.local/bin:${PATH}"

    if command -v uv >/dev/null 2>&1; then
        log_success "uv installed successfully via pip."
    else
        log_error "Failed to install uv."
        exit 1
    fi
}

# Clean build artifacts
clean_build() {
    log_info "Cleaning build artifacts..."

    # Remove virtual environment
    if [ -d "${SCRIPT_DIR}/.venv" ]; then
        rm -rf "${SCRIPT_DIR}/.venv"
        log_info "Removed .venv directory"
    fi

    # Remove PyInstaller output
    if [ -d "${DIST_DIR}" ]; then
        rm -rf "${DIST_DIR}"
        log_info "Removed dist directory"
    fi

    if [ -d "${SCRIPT_DIR}/build" ]; then
        rm -rf "${SCRIPT_DIR}/build"
        log_info "Removed build directory"
    fi

    # Remove .spec backup files
    find "${SCRIPT_DIR}" -name "*.spec~" -delete 2>/dev/null || true

    # Remove __pycache__
    find "${SCRIPT_DIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "${SCRIPT_DIR}" -type f -name "*.pyc" -delete 2>/dev/null || true

    # Remove .deb package if exists
    rm -f "${SCRIPT_DIR}/${APP_NAME}_${APP_VERSION}-${DEB_SUFFIX}_${ARCH}.deb"

    log_success "Build artifacts cleaned."
}

# Build the application with uv and PyInstaller
build_app() {
    log_info "Building application with uv and PyInstaller..."

    # Change to source directory
    cd "${SCRIPT_DIR}"

    # Ensure PATH includes uv
    if [ -f "${HOME}/.local/bin/uv" ]; then
        export PATH="${HOME}/.local/bin:${PATH}"
    fi

    # Check if uv is available (use pip fallback if not)
    if command -v uv >/dev/null 2>&1; then
        log_info "Using uv for virtual environment management..."
        uv venv .venv
    else
        log_info "Using Python venv (uv not available)..."
        python3 -m venv .venv
    fi

    # Activate virtual environment
    source .venv/bin/activate

    # Upgrade pip
    log_info "Upgrading pip..."
    pip install --upgrade pip wheel

    # Install PyInstaller
    log_info "Installing PyInstaller..."
    pip install pyinstaller

    # Install application dependencies
    log_info "Installing application dependencies..."
    pip install -r requirements.txt

    # Build with PyInstaller
    log_info "Running PyInstaller..."
    pyinstaller dlDesktop.spec --noconfirm

    # Check if executable was created
    if [ -f "${DIST_DIR}/Img2Sketch" ]; then
        log_success "Application built successfully: ${DIST_DIR}/Img2Sketch"
    else
        log_error "Build failed - executable not found."
        exit 1
    fi

    # Make executable
    chmod +x "${DIST_DIR}/Img2Sketch"
}

# Create Debian package
create_deb_package() {
    log_info "Creating Debian package..."

    cd "${SCRIPT_DIR}"

    # Create package directory structure
    PACKAGE_ROOT="${PACKAGE_DIR}/img2sketch-${APP_VERSION}-${ARCH}"
    mkdir -p "${PACKAGE_ROOT}/opt/${APP_NAME}"
    mkdir -p "${PACKAGE_ROOT}/usr/bin"
    mkdir -p "${PACKAGE_ROOT}/usr/share/applications"
    mkdir -p "${PACKAGE_ROOT}/usr/share/pixmaps"
    mkdir -p "${PACKAGE_ROOT}/DEBIAN"

    # Install the main binary
    log_info "Installing main binary..."
    install -m 755 "${DIST_DIR}/Img2Sketch" "${PACKAGE_ROOT}/opt/${APP_NAME}/"

    # Create symlink
    ln -sf "/opt/${APP_NAME}/Img2Sketch" "${PACKAGE_ROOT}/usr/bin/${APP_NAME}"

    # Install desktop entry
    log_info "Installing desktop entry..."
    install -m 644 debian/img2sketch.desktop "${PACKAGE_ROOT}/usr/share/applications/"

    # Install icon
    log_info "Installing icon..."
    install -m 644 data/images/favicon.png "${PACKAGE_ROOT}/usr/share/pixmaps/${APP_NAME}.png"

    # Install maintainer scripts
    log_info "Installing maintainer scripts..."
    install -m 755 debian/postinst "${PACKAGE_ROOT}/DEBIAN/postinst"
    install -m 755 debian/prerm "${PACKAGE_ROOT}/DEBIAN/prerm"

    # Create control file (package metadata)
    log_info "Creating package metadata..."
    cat > "${PACKAGE_ROOT}/DEBIAN/control" << EOF
Package: ${APP_NAME}
Version: ${APP_VERSION}-${DEB_SUFFIX}
Architecture: ${ARCH}
Maintainer: DasLearning Team <support@daslearning.in>
Depends: ffmpeg, libavcodec-extra, libavformat59 | libavformat-dev, libswscale7 | libswscale-dev, zlib1g, libgl1-mesa-glx, libglib2.0-0, libstdc++6, libgcc-s1, libc6, libx11-6, libxext6, libxrender1, libxinerama1, libxcursor1, libxrandr2, libxi6, libasound2
Description: Offline Image to Animation Maker
 An open-source, cross-platform, offline application that converts
 static images into sketch-style animation videos.
EOF

    # Build the .deb package
    log_info "Building .deb package..."
    dpkg-deb --build --root="${PACKAGE_ROOT}" -- "${DEB_OUTPUT_DIR}/${APP_NAME}_${APP_VERSION}-${DEB_SUFFIX}_${ARCH}.deb"

    # Verify package was created
    if [ -f "${DEB_OUTPUT_DIR}/${APP_NAME}_${APP_VERSION}-${DEB_SUFFIX}_${ARCH}.deb" ]; then
        log_success "Debian package created: ${DEB_OUTPUT_DIR}/${APP_NAME}_${APP_VERSION}-${DEB_SUFFIX}_${ARCH}.deb"

        # Show package info
        log_info "Package info:"
        dpkg-deb --info "${DEB_OUTPUT_DIR}/${APP_NAME}_${APP_VERSION}-${DEB_SUFFIX}_${ARCH}.deb"
    else
        log_error "Failed to create .deb package."
        exit 1
    fi
}

# Main function
main() {
    local do_clean=false
    local install_deps=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clean)
                do_clean=true
                shift
                ;;
            --install-deps)
                install_deps=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    log_info "Starting img2sketch Debian package build..."

    # Check prerequisites
    check_root

    # Install dependencies if requested
    if [ "$install_deps" = true ]; then
        install_dependencies
    fi

    # Clean if requested
    if [ "$do_clean" = true ]; then
        clean_build
    fi

    # Build the application
    build_app

    # Create Debian package
    create_deb_package

    log_success "Build complete!"
    log_info "Package location: ${DEB_OUTPUT_DIR}/${APP_NAME}_${APP_VERSION}-${DEB_SUFFIX}_${ARCH}.deb"
}

# Run main function
main "$@"