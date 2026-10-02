#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checks_dir="$repo_dir/.build/checks"
mkdir -p "$checks_dir"

run_check() {
  local name="$1"
  shift
  local source
  local sources=()
  for source in "$@"; do
    sources+=("$repo_dir/$source")
  done
  swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
    "${sources[@]}" -o "$checks_dir/$name"
  "$checks_dir/$name"
}

run_check overview-dock-identity \
  QuietLens/Core/OverviewDetector.swift Tests/OverviewDockIdentityCheck.swift
run_check settings-delivery \
  QuietLens/Core/CommittedSettingsEffect.swift Tests/SettingsDeliveryCheck.swift
run_check overlay-timer-cancellation \
  QuietLens/Core/OverlayTimers.swift Tests/OverlayTimerCancellationCheck.swift
run_check input-monitor-lifecycle \
  QuietLens/Core/ShakeDetector.swift QuietLens/Core/HotkeyManager.swift \
  Tests/InputMonitorLifecycleCheck.swift
run_check window-restoration \
  QuietLens/Core/WindowRaiser.swift Tests/WindowRaiserCheck.swift
run_check window-corner-cache \
  QuietLens/Core/WindowCornerRadii.swift QuietLens/Core/WindowCornerReader.swift \
  Tests/WindowCornerCacheCheck.swift
run_check focus-window-selection \
  QuietLens/Core/FocusWindowSelection.swift Tests/FocusWindowSelectionCheck.swift
run_check cutout-geometry \
  QuietLens/Core/WindowCornerRadii.swift QuietLens/Overlay/CutoutGeometry.swift \
  Tests/CutoutGeometryCheck.swift
run_check overlay-fade-state \
  QuietLens/Overlay/OverlayFadeState.swift Tests/OverlayFadeStateCheck.swift
run_check overlay-shader \
  QuietLens/Models/ShaderMode.swift QuietLens/Overlay/OverlayShader.swift \
  Tests/OverlayShaderCheck.swift
run_check overlay-manager-lifecycle \
  QuietLens/Core/OverlayManager.swift QuietLens/Core/FocusWindowSelection.swift \
  QuietLens/Core/WindowCornerRadii.swift QuietLens/Overlay/OverlayDisplay.swift \
  QuietLens/Overlay/CutoutGeometry.swift Tests/OverlayManagerLifecycleCheck.swift

# Checks do not require a signing identity or install the product.
QUIET_LENS_SIGNING_TEAM= bash "$repo_dir/scripts/build.sh" build
QUIET_LENS_SIGNING_TEAM= bash "$repo_dir/scripts/build.sh" analyze
