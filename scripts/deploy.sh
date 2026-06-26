#!/usr/bin/env bash
# =============================================================================
# deploy.sh  –  Deploy all CloudFormation stacks in the correct order
# Usage: ./scripts/deploy.sh [--region us-east-1] [--project my-project]
# =============================================================================
set -euo pipefail

# ─── DEFAULTS ────────────────────────────────────────────────────────────────
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROJECT_NAME="project1-webapp"
STACKS_DIR="$(cd "$(dirname "$0")/../cloudformation/stacks" && pwd)"
DOMAIN_NAME=""
ALERT_EMAIL=""
DB_PASSWORD=""
CERT_ARN=""

# ─── ARGUMENT PARSING ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)         REGION="$2";       shift 2 ;;
    --project)        PROJECT_NAME="$2"; shift 2 ;;
    --domain)         DOMAIN_NAME="$2";  shift 2 ;;
    --email)          ALERT_EMAIL="$2";  shift 2 ;;
    --db-password)    DB_PASSWORD="$2";  shift 2 ;;
    --cert-arn)       CERT_ARN="$2";     shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── VALIDATION ──────────────────────────────────────────────────────────────
if [[ -z "$ALERT_EMAIL" ]]; then
  echo "ERROR: --email is required (e.g. --email ops@example.com)"
  exit 1
fi

if [[ -z "$DB_PASSWORD" ]]; then
  echo "ERROR: --db-password is required (min 8 characters)"
  exit 1
fi

if [[ -z "$DOMAIN_NAME" ]]; then
  echo "WARNING: --domain not provided. Skipping Route53 stack."
fi

# ─── HELPERS ─────────────────────────────────────────────────────────────────
log()     { echo -e "\033[1;34m[$(date '+%H:%M:%S')] $*\033[0m"; }
success() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] ✓ $*\033[0m"; }
error()   { echo -e "\033[1;31m[$(date '+%H:%M:%S')] ✗ $*\033[0m"; exit 1; }

deploy_stack() {
  local stack_name="$1"
  local template_file="$2"
  shift 2
  local params=("$@")

  log "Deploying stack: $stack_name"

  local param_overrides=()
  for p in "${params[@]}"; do
    param_overrides+=("$p")
  done

  aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "$stack_name" \
    --template-file "$template_file" \
    --parameter-overrides "ProjectName=$PROJECT_NAME" "${param_overrides[@]}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --tags "Project=$PROJECT_NAME" "ManagedBy=CloudFormation" "DeployedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  success "Stack $stack_name deployed successfully"
}

# ─── VERIFY AWS CREDENTIALS ──────────────────────────────────────────────────
log "Verifying AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
success "Deploying to Account: $ACCOUNT_ID | Region: $REGION | Project: $PROJECT_NAME"

# ─── STACK 1: VPC ────────────────────────────────────────────────────────────
deploy_stack \
  "${PROJECT_NAME}-vpc" \
  "${STACKS_DIR}/01-vpc.yaml"

# ─── STACK 2: SECURITY GROUPS ────────────────────────────────────────────────
deploy_stack \
  "${PROJECT_NAME}-security-groups" \
  "${STACKS_DIR}/02-security-groups.yaml"

# ─── STACK 3: RDS ────────────────────────────────────────────────────────────
deploy_stack \
  "${PROJECT_NAME}-rds" \
  "${STACKS_DIR}/03-rds.yaml" \
  "DBMasterPassword=$DB_PASSWORD"

log "Waiting for RDS to be available (this may take 10-15 minutes)..."
aws rds wait db-instance-available \
  --db-instance-identifier "${PROJECT_NAME}-db" \
  --region "$REGION"
success "RDS instance is available"

# ─── STACK 4: ALB + WAF ──────────────────────────────────────────────────────
CERT_PARAM=""
if [[ -n "$CERT_ARN" ]]; then
  CERT_PARAM="CertificateArn=$CERT_ARN"
fi

deploy_stack \
  "${PROJECT_NAME}-alb-waf" \
  "${STACKS_DIR}/04-alb-waf.yaml" \
  ${CERT_PARAM:+"$CERT_PARAM"}

# ─── STACK 5: EC2 + ASG ──────────────────────────────────────────────────────
deploy_stack \
  "${PROJECT_NAME}-ec2-asg" \
  "${STACKS_DIR}/05-ec2-asg.yaml"

# ─── STACK 6: CLOUDFRONT ─────────────────────────────────────────────────────
deploy_stack \
  "${PROJECT_NAME}-cloudfront" \
  "${STACKS_DIR}/06-cloudfront.yaml"

# ─── STACK 7: ROUTE 53 (optional) ────────────────────────────────────────────
if [[ -n "$DOMAIN_NAME" ]]; then
  deploy_stack \
    "${PROJECT_NAME}-route53" \
    "${STACKS_DIR}/07-route53.yaml" \
    "DomainName=$DOMAIN_NAME"

  log "⚠️  Update your domain registrar with these name servers:"
  aws cloudformation describe-stacks \
    --stack-name "${PROJECT_NAME}-route53" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='HostedZoneNameServers'].OutputValue" \
    --output text
fi

# ─── STACK 8: MONITORING ─────────────────────────────────────────────────────
deploy_stack \
  "${PROJECT_NAME}-monitoring" \
  "${STACKS_DIR}/08-monitoring.yaml" \
  "AlertEmail=$ALERT_EMAIL"

# ─── SUMMARY ─────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════════"
success "All stacks deployed successfully!"
echo ""
echo "  ALB DNS Name:"
aws cloudformation list-exports \
  --region "$REGION" \
  --query "Exports[?Name=='${PROJECT_NAME}-ALBDNSName'].Value" \
  --output text

echo "  CloudFront Domain:"
aws cloudformation list-exports \
  --region "$REGION" \
  --query "Exports[?Name=='${PROJECT_NAME}-CloudFrontDomainName'].Value" \
  --output text

echo ""
echo "  CloudWatch Dashboard:"
echo "  https://${REGION}.console.aws.amazon.com/cloudwatch/home#dashboards:name=${PROJECT_NAME}-main-dashboard"
echo "══════════════════════════════════════════════════════════════════"
