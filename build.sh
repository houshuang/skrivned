#!/bin/bash
set -e
swift build -c release
cp .build/release/skrivned ~/.local/bin/
codesign -s - ~/.local/bin/skrivned
echo "Installed and signed ~/.local/bin/skrivned"
