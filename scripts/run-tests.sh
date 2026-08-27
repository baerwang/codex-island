#!/bin/bash
# Compiles the standalone value-layer test harnesses. No XCTest/SPM — mirrors
# build.sh's bare-swiftc setup.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR"' EXIT

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/notch-height-tests" \
  Sources/Model/NotchInfo.swift \
  Sources/Model/IslandSpacingStore.swift \
  Sources/Model/PreferenceStorage.swift \
  Tests/NotchHeightTests.swift

"$OUT_DIR/notch-height-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/usage-merge-tests" \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift \
  Tests/UsageMergeTests.swift

"$OUT_DIR/usage-merge-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/alert-decision-tests" \
  Sources/Model/PreferenceStorage.swift \
  Sources/Model/AppEnvironment.swift \
  Sources/Model/RefreshIntervalStore.swift \
  Sources/Model/ProviderVisibilityStore.swift \
  Sources/Model/AlertThresholdStore.swift \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Model/QuotaWindowPreferenceStore.swift \
  Sources/Model/CLIProviderConfig.swift \
  Sources/Usage/AppUsage.swift \
  Sources/Usage/CompactQuotaSelection.swift \
  Sources/Usage/CLIStatusProbe.swift \
  Sources/Usage/UsageFetcher.swift \
  Sources/Usage/CodexHeadlineSelection.swift \
  Sources/Usage/UsageHistory.swift \
  Sources/Usage/UsageStore.swift \
  Sources/Model/AlertEngine.swift \
  Tests/AlertDecisionTests.swift

"$OUT_DIR/alert-decision-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/compact-quota-selection-tests" \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift \
  Sources/Usage/CompactQuotaSelection.swift \
  Tests/CompactQuotaSelectionTests.swift

"$OUT_DIR/compact-quota-selection-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/codex-headline-selection-tests" \
  Sources/Model/PreferenceStorage.swift \
  Sources/Model/CLIProviderConfig.swift \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift \
  Sources/Usage/CodexHeadlineSelection.swift \
  Tests/CodexHeadlineSelectionTests.swift

"$OUT_DIR/codex-headline-selection-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/codex-profile-config-tests" \
  Sources/Model/PreferenceStorage.swift \
  Sources/Model/CLIProviderConfig.swift \
  Sources/Model/CodexCostProfileStore.swift \
  Tests/CodexProfileConfigTests.swift

"$OUT_DIR/codex-profile-config-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/cli-usage-parser-tests" \
  Sources/Model/PreferenceStorage.swift \
  Sources/Model/CLIProviderConfig.swift \
  Sources/Model/UsageDisplayModeStore.swift \
  Sources/Usage/AppUsage.swift \
  Sources/Usage/CLIStatusProbe.swift \
  Sources/Usage/UsageFetcher.swift \
  Tests/CLIUsageParserTests.swift

"$OUT_DIR/cli-usage-parser-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-tests" \
  Sources/Cost/TokenEvent.swift \
  Sources/Cost/PricingCatalog.swift \
  Sources/Cost/Pricing.swift \
  Tests/PricingTests.swift

"$OUT_DIR/pricing-tests"

swiftc \
  -parse-as-library \
  -framework AppKit \
  -o "$OUT_DIR/project-cost-tests" \
  Sources/Model/AppLanguageStore.swift \
  Sources/Localization/L10n.swift \
  Sources/Cost/TokenEvent.swift \
  Sources/Cost/PricingCatalog.swift \
  Sources/Cost/Pricing.swift \
  Sources/Cost/CostBucketing.swift \
  Sources/Cost/CostUsage.swift \
  Sources/Cost/CostSummary.swift \
  Tests/ProjectCostTests.swift

"$OUT_DIR/project-cost-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-catalog-tests" \
  Sources/Cost/PricingCatalog.swift \
  Tests/PricingCatalogTests.swift

"$OUT_DIR/pricing-catalog-tests"

swiftc \
  -parse-as-library \
  -sanitize=thread \
  -o "$OUT_DIR/pricing-catalog-race-tests" \
  Sources/Cost/PricingCatalog.swift \
  Tests/PricingCatalogRaceTests.swift

"$OUT_DIR/pricing-catalog-race-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-tests" \
  Sources/Cost/TokenEvent.swift \
  Sources/Cost/PricingCatalog.swift \
  Sources/Cost/Pricing.swift \
  Tests/PricingTests.swift

"$OUT_DIR/pricing-tests"

swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-precedence-tests" \
  Sources/Cost/TokenEvent.swift \
  Sources/Cost/PricingCatalog.swift \
  Sources/Cost/Pricing.swift \
  Tests/PricingPrecedenceTests.swift

"$OUT_DIR/pricing-precedence-tests"
