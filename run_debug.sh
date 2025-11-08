#!/bin/bash

# Script to run Picotron game and show console output
# This helps debug palette loading issues

cd "/Users/rubentipparach/Library/Application Support/Picotron/drive/game-jam"

# Check if Picotron is installed
if [ ! -d "/Applications/Picotron.app" ]; then
    echo "Error: Picotron.app not found in /Applications/"
    exit 1
fi

echo "Running Picotron with dark-neb.p64..."
echo "Console output will appear below:"
echo "========================================"

# Run Picotron and pipe output
/Applications/Picotron.app/Contents/MacOS/picotron dark-neb.p64

echo "========================================"
echo "Picotron closed"
