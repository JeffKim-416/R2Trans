#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R2TRANS_ALLOW_ADHOC=1 "$ROOT_DIR/Scripts/install_app.sh"
