#!/usr/bin/env sh

LDCUP_BASE_URL="https://github.com/kassane/ldcup/releases/latest/download"
LDCUP_INSTALL_DIR="$HOME/.dlang"
ARCHITECTURE=$(uname -m)
case "$ARCHITECTURE" in
    "x86_64") ARCHITECTURE="amd64" ;;
    "arm64"|"aarch64") ARCHITECTURE="arm64" ;;
    *)
        echo "Error: Architecture $ARCHITECTURE is not supported yet."
        exit 1
        ;;
esac

if [ "$(uname)" = "Darwin" ] && [ "$ARCHITECTURE" = "arm64" ]; then
    LDCUP_FILENAME="ldcup-macos-$ARCHITECTURE.zip"
else
    LDCUP_FILENAME="ldcup-ubuntu-24.04-$ARCHITECTURE.zip"
fi
LDCUP_URL="$LDCUP_BASE_URL/$LDCUP_FILENAME"

# Create the installation directory if it doesn't exist
if [ ! -d "$LDCUP_INSTALL_DIR" ]; then
    echo "Creating installation directory at $LDCUP_INSTALL_DIR..."
    mkdir -p "$LDCUP_INSTALL_DIR"
fi

# Check if the existing ldcup exists and remove it
if [ -f "$LDCUP_INSTALL_DIR/ldcup" ]; then
    rm -f "$LDCUP_INSTALL_DIR/ldcup"
    echo "Removed existing ldcup."
fi

if command -v curl >/dev/null 2>&1; then
    # Download using curl
    echo "Downloading ldcup from $LDCUP_URL..."
    if ! curl -L "$LDCUP_URL" -o "$LDCUP_INSTALL_DIR/$LDCUP_FILENAME"; then
        echo "Error: Failed to download ldcup. Please check your internet connection and URL."
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    # Download using wget
    echo "Downloading ldcup from $LDCUP_URL..."
    if ! wget -q "$LDCUP_URL" -O "$LDCUP_INSTALL_DIR/$LDCUP_FILENAME"; then
        echo "Error: Failed to download ldcup. Please check your internet connection and URL."
        exit 1
    fi
else
    echo "Error: Neither curl nor wget found. Please install one of them and try again."
    exit 1
fi
echo "Download complete."

# Extract the downloaded file
echo "Extracting ldcup..."
if ! unzip "$LDCUP_INSTALL_DIR/$LDCUP_FILENAME" -d "$LDCUP_INSTALL_DIR"; then
    echo "Error: Failed to extract $LDCUP_FILENAME. Please check the file and try again."
    rm -f "$LDCUP_INSTALL_DIR/$LDCUP_FILENAME"
    exit 1
fi
echo "Extraction complete."

# Remove the downloaded archive
rm -f "$LDCUP_INSTALL_DIR/$LDCUP_FILENAME"

# Move the new executable
if [ -f "$LDCUP_INSTALL_DIR/ldcup" ]; then
    chmod +x "$LDCUP_INSTALL_DIR/ldcup"
    echo "Made ldcup executable"

    # Set up environment variables
    echo "Setting up environment variables..."
    
    # Add environment variables to shell rc file
    SHELL_RC=""
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -n "$FISH_VERSION" ]; then
        SHELL_RC="$HOME/.config/fish/config.fish"
    fi

    if [ -n "$SHELL_RC" ]; then
        # Remove old entries if they exist
        sed -i '/export LDCUP_DIR=/d' "$SHELL_RC"
        sed -i '/export PATH=\$PATH:\$LDCUP_DIR/d' "$SHELL_RC"

        # Add new entries
        if [ -n "$FISH_VERSION" ]; then
            echo "set -x LDCUP_DIR \"$LDCUP_INSTALL_DIR\"" >> "$SHELL_RC"
            echo 'set -x PATH $PATH $LDCUP_DIR' >> "$SHELL_RC"
        else
            echo "export LDCUP_DIR=\"$LDCUP_INSTALL_DIR\"" >> "$SHELL_RC"
            echo 'export PATH=$PATH:$LDCUP_DIR' >> "$SHELL_RC"
        fi
        
        echo "Environment variables have been added to $SHELL_RC"
        echo "LDCUP_DIR has been set to $LDCUP_INSTALL_DIR"
    else
        echo "Warning: Could not determine shell configuration file. Please manually add the following to your shell's rc file:"
        echo "export LDCUP_DIR=\"$LDCUP_INSTALL_DIR\""
        echo 'export PATH=$PATH:$LDCUP_DIR'
    fi

    # Execute ldcup install
    "$LDCUP_INSTALL_DIR/ldcup" install
else
    echo "Error: ldcup executable not found after extraction. Please check the downloaded files."
    exit 1
fi

echo -e "\nInstallation complete. Please restart your terminal or run 'source $SHELL_RC' to apply changes."