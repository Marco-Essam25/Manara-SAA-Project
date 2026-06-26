#!/usr/bin/env bash
# teardown.sh - Delete all stacks in reverse dependency order
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROJECT_NAME="project1-webapp"

while [[ $# -gt 0 ]]; do
  case $1 in
    --region)  REGION="$2";       shift 2 ;;
    --project) PROJECT_NAME="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log()     { echo -e "\033[1;34m[$(date '+%H:%M:%S')] $*\033[0m"; }
success() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] OK $*\033[0m"; }

delete_stack() {
  local stack_name="$1"
  if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" > /dev/null 2>&1; then
    log "Deleting stack: $stack_name"
    if [[ "$stack_name" == *"rds"* ]]; then
      DB_ID=$(aws cloudformation describe-stack-resource \
        --stack-name "$stack_name" \
        --logical-resource-id DBInstance \
        --region "$REGION" \
        --query "StackResourceDetail.PhysicalResourceId" \
        --output text 2>/dev/null || true)
      if [[ -n "$DB_ID" ]]; then
        aws rds modify-db-instance \
          --db-instance-identifier "$DB_ID" \
          --no-deletion-protection \
          --region "$REGION" \
          --apply-immediately > /dev/null || true
        sleep 15
      fi
    fi
    aws cloudformation delete-stack --stack-name "$stack_name" --region "$REGION"
    aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$REGION"
    success "Stack $stack_name deleted"
  else
    log "Stack $stack_name not found, skipping..."
  fi
}

echo ""
echo "WARNING: This will permanently delete ALL infrastructure for: $PROJECT_NAME"
read -rp "Type the project name to confirm: " CONFIRM
if [[ "$CONFIRM" != "$PROJECT_NAME" ]]; then
  echo "Confirmation failed. Aborting."
  exit 1
fi

delete_stack "${PROJECT_NAME}-monitoring"
delete_stack "${PROJECT_NAME}-route53"
delete_stack "${PROJECT_NAME}-cloudfront"
delete_stack "${PROJECT_NAME}-ec2-asg"
delete_stack "${PROJECT_NAME}-alb-waf"
delete_stack "${PROJECT_NAME}-rds"
delete_stack "${PROJECT_NAME}-security-groups"
delete_stack "${PROJECT_NAME}-vpc"

success "All stacks deleted successfully."
