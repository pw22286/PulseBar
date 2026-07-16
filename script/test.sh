#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$ROOT_DIR/.build/checks"
CHECK_BINARY="$CHECK_DIR/spectrum-analyzer-check"

mkdir -p "$CHECK_DIR"
xcrun swiftc \
  -parse-as-library \
  "$ROOT_DIR/Sources/PulseBar/Services/SpectrumAnalyzer.swift" \
  "$ROOT_DIR/Tests/SpectrumAnalyzerCheck.swift" \
  -o "$CHECK_BINARY"

"$CHECK_BINARY"
