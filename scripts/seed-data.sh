#!/usr/bin/env bash
# Seeds demo data into an empty scratch store (CAPTAINSLOG_STORE_DIR). seed-demo refuses the real store.
set -euo pipefail

echo "Building CLI..."
swift build --quiet

echo "Seeding demo data..."
.build/debug/captains-log seed-demo --pretty
