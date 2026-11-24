#!/bin/sh
# Xcode Cloud runs this after clone. Logic tests do not need a simulator.
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root/ios/MouthyLogic"
swift test
