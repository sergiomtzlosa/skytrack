#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p /tmp/swift-modules
swiftc -module-cache-path /tmp/swift-modules "$DIR/make_icon.swift" -o "$DIR/make_icon"
"$DIR/make_icon" "$DIR/AppIcon@1024.png"
echo "Rendered $DIR/AppIcon@1024.png successfully!"

