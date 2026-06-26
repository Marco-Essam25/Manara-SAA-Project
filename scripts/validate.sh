#!/usr/bin/env bash
# validate.sh - Validate all CloudFormation templates using AWS CLI
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STACKS_DIR="$(cd "$(dirname "$0")/../cloudformation/stacks" && pwd)"
PASS=0
FAIL=0

success() { echo -e "\033[1;32m[PASS]\033[0m $*"; }
error_msg()   { echo -e "\033[1;31m[FAIL]\033[0m $*"; }

echo "Validating CloudFormation templates against region: $REGION"
echo "--------------------------------------------------------------"

for template in "$STACKS_DIR"/*.yaml; do
  name=$(basename "$template")
  OUTPUT=$(aws cloudformation validate-template \
      --template-body "file://${template}" \
      --region "$REGION" 2>&1)
  if [[ $? -eq 0 ]]; then
    success "$name"
    PASS=$((PASS + 1))
  else
    error_msg "$name"
    echo "  $OUTPUT"
    FAIL=$((FAIL + 1))
  fi
done

echo "--------------------------------------------------------------"
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
