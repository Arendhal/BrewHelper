#!/bin/bash
# Compile le moteur d'identité seul (sans l'application) et rejoue Tools/IdentityCheck.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/identity-check" \
  "$ROOT/BrewHelper/Models/BrewPackage.swift" \
  "$ROOT/BrewHelper/Models/CVEVulnerability.swift" \
  "$ROOT/BrewHelper/Services/VulnerabilityMatcher.swift" \
  "$ROOT/BrewHelper/Services/ProductIdentity.swift" \
  "$ROOT/Tools/IdentityCheck/main.swift"
"$OUT/identity-check"
