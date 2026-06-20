#!/bin/zsh
# Kører regressionstests uden Xcode (CLT mangler XCTest/Testing).
# Kompilerer app-kilderne (minus @main-filen) sammen med Tests/checks/main.swift.
set -e
cd "$(dirname "$0")/.."

SOURCES=(Sources/Nyhedsoverblik/*.swift)
# Udelad app-entry (@main kolliderer med main.swift)
SOURCES=(${SOURCES:#*NyhedsoverblikApp.swift})

OUT=$(mktemp -d)/checks
swiftc -O -o "$OUT" "${SOURCES[@]}" Tests/checks/main.swift
"$OUT"
