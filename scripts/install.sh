#!/usr/bin/env sh
# ldcup installer — POSIX sh compatible (Unix/macOS/Linux/FreeBSD)
# For Windows, use install.ps1 instead.
set -eu

LDCUP_BASE_URL="https://github.com/kassane/ldcup/releases/latest/download"
LDCUP_INSTALL_DIR="${LDCUP_INSTALL_DIR:-$HOME/.dlang}"

# ---------------------------------------------------------------------------
# Detect architecture
# ---------------------------------------------------------------------------
ARCHITECTURE=$(uname -m)
case "$ARCHITECTURE" in
    x86_64)          ARCHITECTURE="amd64" ;;
    arm64 | aarch64) ARCHITECTURE="arm64" ;;
    *)
        printf "Error: architecture '%s' is not supported.\n" "$ARCHITECTURE" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Detect OS and select the correct archive.
#
# Available assets (Oct 2025):
#   ldcup-alpine-amd64.tar.xz
#   ldcup-freebsd14.3-amd64.tar.xz
#   ldcup-macos-latest-arm64.tar.xz          (Apple Silicon only)
#   ldcup-ubuntu-22.04-amd64.tar.xz
#   ldcup-ubuntu-22.04-arm-arm64.tar.xz
#   (Windows: use install.ps1)
# ---------------------------------------------------------------------------
OS=$(uname -s)
LDCUP_FILENAME=""
LDCUP_SHA256=""

case "$OS" in
    Darwin)
        if [ "$ARCHITECTURE" = "arm64" ]; then
            LDCUP_FILENAME="ldcup-macos-latest-arm64.tar.xz"
            LDCUP_SHA256="8e6846f90f21c9e87acedef4c990fc95222ee8d00dff6989e3947cba2cdbd465"
        else
            printf "Error: macOS on Intel (x86_64) is not supported.\n" >&2
            printf "Only Apple Silicon (arm64) builds are available.\n" >&2
            exit 1
        fi
        ;;
    Linux)
        if [ -f /etc/alpine-release ] || command -v apk >/dev/null 2>&1; then
            if [ "$ARCHITECTURE" = "amd64" ]; then
                LDCUP_FILENAME="ldcup-alpine-amd64.tar.xz"
                LDCUP_SHA256="bea85ee81c26831670b89fba2006c2a1f7a150ab4a554af6715871254abb0172"
            else
                printf "Error: Alpine Linux on arm64 is not supported.\n" >&2
                exit 1
            fi
        elif [ "$ARCHITECTURE" = "arm64" ]; then
            LDCUP_FILENAME="ldcup-ubuntu-22.04-arm-arm64.tar.xz"
            LDCUP_SHA256="2b5ddaa142923a9217c24367ab9255ccd28f6a1aa0dec0db47da9c0bce94255b"
        else
            LDCUP_FILENAME="ldcup-ubuntu-22.04-amd64.tar.xz"
            LDCUP_SHA256="59a9bc3486b5caa0663658c038300cfeda0e25b07623f34fa1e32dc583fc9032"
        fi
        ;;
    FreeBSD)
        if [ "$ARCHITECTURE" = "amd64" ]; then
            LDCUP_FILENAME="ldcup-freebsd14.3-amd64.tar.xz"
            LDCUP_SHA256="b6b46f39c3db256c85c0c20f2da4b8e6c9e2f96eec253542e09ffc8527f8bc59"
        else
            printf "Error: FreeBSD on arm64 is not currently supported.\n" >&2
            exit 1
        fi
        ;;
    *)
        printf "Error: operating system '%s' is not supported by this script.\n" "$OS" >&2
        printf "For Windows, use install.ps1 instead.\n" >&2
        exit 1
        ;;
esac

LDCUP_URL="$LDCUP_BASE_URL/$LDCUP_FILENAME"

# ---------------------------------------------------------------------------
# Prepare installation directory
# ---------------------------------------------------------------------------
if [ ! -d "$LDCUP_INSTALL_DIR" ]; then
    printf "Creating installation directory at %s ...\n" "$LDCUP_INSTALL_DIR"
    mkdir -p "$LDCUP_INSTALL_DIR"
fi

# Remove stale binary so a previous partial install cannot interfere.
if [ -f "$LDCUP_INSTALL_DIR/ldcup" ]; then
    rm -f "$LDCUP_INSTALL_DIR/ldcup"
    printf "Removed existing ldcup binary.\n"
fi

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
ARCHIVE="$LDCUP_INSTALL_DIR/$LDCUP_FILENAME"

printf "Downloading ldcup from %s ...\n" "$LDCUP_URL"
if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL "$LDCUP_URL" -o "$ARCHIVE"; then
        printf "Error: download failed. Check your internet connection and the URL.\n" >&2
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    if ! wget -q "$LDCUP_URL" -O "$ARCHIVE"; then
        printf "Error: download failed. Check your internet connection and the URL.\n" >&2
        exit 1
    fi
else
    printf "Error: neither curl nor wget is available. Please install one and retry.\n" >&2
    exit 1
fi
printf "Download complete.\n"

# ---------------------------------------------------------------------------
# Verify SHA256 checksum
# ---------------------------------------------------------------------------
printf "Verifying checksum ...\n"
ACTUAL_SHA256=""
if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    # macOS ships shasum but not sha256sum
    ACTUAL_SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
else
    printf "Warning: no sha256sum or shasum found; skipping checksum verification.\n"
fi

if [ -n "$ACTUAL_SHA256" ]; then
    if [ "$ACTUAL_SHA256" != "$LDCUP_SHA256" ]; then
        printf "Error: checksum mismatch!\n" >&2
        printf "  expected: %s\n" "$LDCUP_SHA256" >&2
        printf "  got:      %s\n" "$ACTUAL_SHA256" >&2
        rm -f "$ARCHIVE"
        exit 1
    fi
    printf "Checksum OK.\n"
fi

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
printf "Extracting %s ...\n" "$LDCUP_FILENAME"
if ! tar -xJf "$ARCHIVE" -C "$LDCUP_INSTALL_DIR"; then
    printf "Error: extraction failed. The archive may be corrupt.\n" >&2
    rm -f "$ARCHIVE"
    exit 1
fi
rm -f "$ARCHIVE"
printf "Extraction complete.\n"

# ---------------------------------------------------------------------------
# Verify binary and make executable
# ---------------------------------------------------------------------------
LDCUP_BIN="$LDCUP_INSTALL_DIR/ldcup"
if [ ! -f "$LDCUP_BIN" ]; then
    printf "Error: ldcup binary not found at %s after extraction.\n" "$LDCUP_BIN" >&2
    exit 1
fi
chmod +x "$LDCUP_BIN"
printf "ldcup binary is ready at %s\n" "$LDCUP_BIN"

# ---------------------------------------------------------------------------
# Detect shell configuration file via $SHELL (not $ZSH_VERSION etc.)
# ---------------------------------------------------------------------------
SHELL_NAME=$(basename "${SHELL:-sh}")
case "$SHELL_NAME" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
    fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
    *)    SHELL_RC="$HOME/.profile" ;;
esac

# ---------------------------------------------------------------------------
# Write environment variables
# Portable line removal: avoids the BSD sed vs GNU sed -i incompatibility.
# ---------------------------------------------------------------------------
remove_lines() {
    _file="$1"
    _pattern="$2"
    if [ -f "$_file" ]; then
        _tmp=$(mktemp)
        grep -v "$_pattern" "$_file" > "$_tmp" || true
        mv "$_tmp" "$_file"
    fi
}

printf "Setting up environment variables in %s ...\n" "$SHELL_RC"
mkdir -p "$(dirname "$SHELL_RC")"
touch "$SHELL_RC"

remove_lines "$SHELL_RC" "LDCUP_DIR="
remove_lines "$SHELL_RC" 'PATH=.*LDCUP_DIR'

if [ "$SHELL_NAME" = "fish" ]; then
    printf 'set -gx LDCUP_DIR "%s"\n' "$LDCUP_INSTALL_DIR" >> "$SHELL_RC"
    printf 'set -gx PATH $PATH $LDCUP_DIR\n'               >> "$SHELL_RC"
else
    printf 'export LDCUP_DIR="%s"\n' "$LDCUP_INSTALL_DIR"  >> "$SHELL_RC"
    printf 'export PATH=$PATH:$LDCUP_DIR\n'                 >> "$SHELL_RC"
fi

printf "Environment variables written to %s\n" "$SHELL_RC"

# ---------------------------------------------------------------------------
# Bootstrap: install ldc2-latest via the freshly installed ldcup
# ---------------------------------------------------------------------------
printf "\nBootstrapping ldc2-latest ...\n"
"$LDCUP_BIN" install ldc2-latest --verbose

# Reload config in current session (POSIX: "." not "source")
# shellcheck disable=SC1090
. "$SHELL_RC"

printf "\nInstallation complete.\n"
printf "Restart your terminal or run:  . %s\n" "$SHELL_RC"