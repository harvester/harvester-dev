#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=0
CHECKED=0

check_command() {
  local cmd="$1"
  local desc="${2:-}"
  CHECKED=$((CHECKED + 1))

  if command -v "$cmd" &>/dev/null; then
    local path
    path=$(command -v "$cmd")
    echo -e "${GREEN}✓${NC} $cmd found at $path"
  else
    echo -e "${RED}✗${NC} $cmd not found${desc:+ (required: $desc)}"
    FAILED=$((FAILED + 1))
  fi
}

check_go() {
  local min_version="$1"
  CHECKED=$((CHECKED + 1))

  if ! command -v go &>/dev/null; then
    echo -e "${RED}✗${NC} Go not found (required: ${min_version})"
    FAILED=$((FAILED + 1))
    return
  fi

  local version
  version=$(go env GOVERSION)
  if [[ "$version" == "go"* ]]; then
    version="${version#go}"
  fi

  local req="$min_version"
  req="${req#v}"  # strip leading 'v' for comparison

  if [[ "$version" == "$req"* ]]; then
    echo -e "${GREEN}✓${NC} Go $version (minimum required: $min_version)"
  else
    echo -e "${RED}✗${NC} Go $version installed, but minimum required is $min_version"
    FAILED=$((FAILED + 1))
  fi
}

check_pyaml() {
  CHECKED=$((CHECKED + 1))

  if ! python3 -c "import yaml" &>/dev/null; then
    echo -e "${RED}✗${NC} PyYAML not found (run: pip3 install pyyaml)"
    FAILED=$((FAILED + 1))
  else
    local version
    version=$(python3 -c "import yaml; print(yaml.__version__)" 2>/dev/null)
    echo -e "${GREEN}✓${NC} PyYAML $version installed"
  fi
}

check_command "task"
check_command "terraform"
check_command "yq"
check_command "virsh"
check_go "v1.26"
check_pyaml

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo -e "${RED}Prerequisites check failed: $FAILED/$CHECKED commands not found.${NC}"
  exit 1
fi

echo "All $CHECKED prerequisites are satisfied."
exit 0
