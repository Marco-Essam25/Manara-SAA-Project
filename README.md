# Project 1 — Scalable Web Application with ALB and Auto Scaling

## Architecture Overview

This project deploys a **production-grade, highly available web application** on AWS using a pure AWS-native approach with CloudFormation IaC. The architecture spans **two Availability Zones** and uses AWS-managed services for security, scalability, and observability.

---

## Solution Architecture Diagram

```
                          ┌─────────────────────────────────────────────────────────────┐
                          │                        INTERNET                              │
                          └──────────────────────────┬──────────────────────────────────┘
                                                     │
                          ┌──────────────────────────▼──────────────────────────────────┐
                          │              Route 53 (DNS + Health Checks)                  │
                          │  Alias A record ──► ALB  │  CNAME ──► CloudFront            │
                          └──────────────────────────┬──────────────────────────────────┘
                                                     │
                          ┌──────────────────────────▼──────────────────────────────────┐
                          │              CloudFront Distribution                          │
                          │  /static/* /images/* /assets/* ──► S3 (cache 1yr)           │
                          │  Default + /api/* ──► ALB (no cache)                        │
                          │  WAF (CLOUDFRONT scope, optional)                            │
                          └──────────────────────────┬──────────────────────────────────┘
                                                     │
┌────────────────────────────────── AWS Region (us-east-1) ───────────────────────────────────────┐
│                                                     │                                            │
│  ┌──────────────────────────────────────────────────▼────────────────────────────────────────┐  │
│  │                              VPC  10.0.0.0/16                                              │  │
│  │                                                                                            │  │
│  │  ┌─────────────────────────── Public Tier ───────────────────────────────────────────┐   │  │
│  │  │                                                                                    │   │  │
│  │  │  ┌──────────────────────────┐         ┌──────────────────────────┐                │   │  │
│  │  │  │  Public Subnet AZ1       │         │  Public Subnet AZ2       │                │   │  │
│  │  │  │  10.0.1.0/24             │         │  10.0.2.0/24             │                │   │  │
│  │  │  │                          │         │                          │                │   │  │
│  │  │  │  [ALB Node]  [NAT GW 1]  │         │  [ALB Node]  [NAT GW 2]  │                │   │  │
│  │  │  │                          │         │                          │                │   │  │
│  │  │  └──────────────────────────┘         └──────────────────────────┘                │   │  │
│  │  │                                                                                    │   │  │
│  │  │    ┌────────────────────── WAF WebACL (REGIONAL) ─────────────────────────┐       │   │  │
│  │  │    │  • AWSManagedRulesCommonRuleSet (OWASP Top 10)                       │       │   │  │
│  │  │    │  • AWSManagedRulesSQLiRuleSet                                         │       │   │  │
│  │  │    │  • AWSManagedRulesKnownBadInputsRuleSet                               │       │   │  │
│  │  │    │  • AWSManagedRulesAmazonIpReputationList                              │       │   │  │
│  │  │    │  • Rate Limit: 2000 req/5min per IP                                  │       │   │  │
│  │  │    └─────────────────────────────────────────────────────────────────────┘       │   │  │
│  │  │                                                                                    │   │  │
│  │  │    ┌───────────────────── Application Load Balancer ──────────────────────┐       │   │  │
│  │  │    │  HTTP :80 → redirect HTTPS :443                                      │       │   │  │
│  │  │    │  HTTPS :443 → TLS 1.3, forward to Target Group                      │       │   │  │
│  │  │    │  /api/* listener rule → same Target Group                            │       │   │  │
│  │  │    │  Health check: GET /health → HTTP 200                                │       │   │  │
│  │  │    └─────────────────────────────────────────────────────────────────────┘       │   │  │
│  │  │                         │                     │                                   │   │  │
│  │  └─────────────────────────┼─────────────────────┼───────────────────────────────────┘   │  │
│  │                            │                     │                                         │  │
│  │  ┌─────────────────────────┼─── Private App Tier ┼─────────────────────────────────────┐  │  │
│  │  │                         │                     │                                     │  │  │
│  │  │  ┌──────────────────────▼───────┐   ┌─────────▼────────────────────┐               │  │  │
│  │  │  │  Private App Subnet AZ1      │   │  Private App Subnet AZ2      │               │  │  │
│  │  │  │  10.0.3.0/24                 │   │  10.0.4.0/24                 │               │  │  │
│  │  │  │                              │   │                              │               │  │  │
│  │  │  │  [EC2 t3.medium]             │   │  [EC2 t3.medium]             │               │  │  │
│  │  │  │   Nginx → App :8080          │   │   Nginx → App :8080          │               │  │  │
│  │  │  │   SSM Session Manager        │   │   SSM Session Manager        │               │  │  │
│  │  │  │   CloudWatch Agent           │   │   CloudWatch Agent           │               │  │  │
│  │  │  │   IMDSv2 enforced            │   │   IMDSv2 enforced            │               │  │  │
│  │  │  └──────────────────────────────┘   └──────────────────────────────┘               │  │  │
│  │  │                                                                                     │  │  │
│  │  │    Auto Scaling Group: min=2  desired=2  max=8                                     │  │  │
│  │  │    • Target Tracking: CPU @ 60%                                                    │  │  │
│  │  │    • Target Tracking: ALB RequestCount/target @ 1000                               │  │  │
│  │  │    • Step Scaling Out: +1 @ CPU>80%, +2 @ CPU>100%                                │  │  │
│  │  │    • Step Scaling In:  -1 @ CPU<20%                                                │  │  │
│  │  │    • Scheduled: 4 instances (08:00 UTC) → 2 (20:00 UTC)                           │  │  │
│  │  │                                                                                     │  │  │
│  │  └─────────────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                            │  │
│  │  ┌──────────────────────────── Private DB Tier ───────────────────────────────────────┐   │  │
│  │  │                                                                                     │   │  │
│  │  │  ┌──────────────────────────────┐     ┌──────────────────────────────┐             │   │  │
│  │  │  │  Private DB Subnet AZ1       │     │  Private DB Subnet AZ2       │             │   │  │
│  │  │  │  10.0.5.0/24                 │     │  10.0.6.0/24                 │             │   │  │
│  │  │  │                              │     │                              │             │   │  │
│  │  │  │  [RDS MySQL 8.0 PRIMARY]     │────▶│  [RDS MySQL 8.0 STANDBY]    │             │   │  │
│  │  │  │   Multi-AZ, gp3, encrypted   │     │   Auto failover <120s        │             │   │  │
│  │  │  │   KMS CMK, backups 7 days     │     │                              │             │   │  │
│  │  │  └──────────────────────────────┘     └──────────────────────────────┘             │   │  │
│  │  │                                                                                     │   │  │
│  │  └─────────────────────────────────────────────────────────────────────────────────────┘   │  │
│  │                                                                                            │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                   │
│  ┌─────────────────────────────── Supporting Services ───────────────────────────────────────┐   │
│  │  SSM Parameter Store  │  Secrets Manager  │  Systems Manager Session Manager              │   │
│  │  CloudWatch Logs      │  CloudWatch Alarms │  CloudWatch Dashboard                        │   │
│  │  SNS (email alerts)   │  VPC Flow Logs     │  S3 (static assets + CF logs)                │   │
│  └───────────────────────────────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
project1-scalable-web-app/
├── cloudformation/
│   └── stacks/
│       ├── 01-vpc.yaml              # VPC, subnets, IGW, NAT GWs, route tables, NACLs, flow logs
│       ├── 02-security-groups.yaml  # SGs for ALB, EC2, RDS, VPC endpoints + SSM endpoints
│       ├── 03-rds.yaml              # RDS MySQL Multi-AZ, KMS, parameter group, backups
│       ├── 04-alb-waf.yaml          # ALB, target group, HTTP/HTTPS listeners, WAF WebACL
│       ├── 05-ec2-asg.yaml          # Launch Template, ASG, target tracking + step scaling
│       ├── 06-cloudfront.yaml       # CloudFront, S3 bucket, cache policies, OAI
│       ├── 07-route53.yaml          # Hosted zone, alias records, health checks
│       └── 08-monitoring.yaml       # SNS, CloudWatch alarms, dashboard, log groups
├── scripts/
│   ├── deploy.sh                    # Ordered deployment of all 8 stacks
│   ├── teardown.sh                  # Reverse-order teardown with safety confirmation
│   └── validate.sh                  # CloudFormation template validation
├── docs/
│   └── deployment-guide.md          # Step-by-step deployment instructions
├── architecture/
│   └── ARCHITECTURE.md              # Detailed architecture decisions
└── README.md                        # This file
```

---

## Key AWS Services Used

| Service | Role | Configuration |
|---|---|---|
| **VPC** | Network isolation | 10.0.0.0/16, 3 subnet tiers, 2 AZs |
| **Internet Gateway** | Internet access for public subnets | Attached to VPC |
| **NAT Gateway** | Outbound internet for private subnets | One per AZ (HA) |
| **NACLs** | Subnet-level stateless firewall | Separate NACLs per tier |
| **Security Groups** | Instance-level stateful firewall | Least-privilege, SG references |
| **ALB** | Layer 7 load balancing | HTTP→HTTPS redirect, path routing |
| **WAF** | Web application firewall | OWASP Top 10, SQLi, rate limiting |
| **EC2** | Compute | t3.medium, Amazon Linux 2023, IMDSv2 |
| **Auto Scaling Group** | Dynamic scaling | Target tracking (CPU 60%) + step scaling |
| **Launch Template** | Instance configuration | Nginx + CloudWatch Agent, SSM role |
| **RDS MySQL** | Managed relational database | Multi-AZ, gp3, KMS encrypted |
| **CloudFront** | CDN + edge caching | Static assets (S3), dynamic (ALB) |
| **S3** | Static asset storage | Versioned, encrypted, OAI-protected |
| **Route 53** | DNS management | Alias to ALB, health checks, CNAME to CF |
| **Systems Manager** | Bastion-free instance access | Session Manager via VPC endpoints |
| **CloudWatch** | Monitoring & alerting | Alarms for CPU, latency, 5xx, RDS |
| **SNS** | Notifications | Email alerts for all alarms |
| **KMS** | Encryption key management | CMK for RDS, EBS volumes |
| **IAM** | Identity & access control | Least-privilege EC2 role |
| **VPC Flow Logs** | Network traffic logging | All traffic → CloudWatch Logs |

---

## Network Design

### Subnet Layout

| Subnet | CIDR | AZ | Purpose |
|---|---|---|---|
| Public AZ1 | 10.0.1.0/24 | AZ1 | ALB nodes, NAT Gateway 1 |
| Public AZ2 | 10.0.2.0/24 | AZ2 | ALB nodes, NAT Gateway 2 |
| Private App AZ1 | 10.0.3.0/24 | AZ1 | EC2 instances (ASG) |
| Private App AZ2 | 10.0.4.0/24 | AZ2 | EC2 instances (ASG) |
| Private DB AZ1 | 10.0.5.0/24 | AZ1 | RDS Primary |
| Private DB AZ2 | 10.0.6.0/24 | AZ2 | RDS Standby |

### Security Group Rules (Least Privilege)

```
Internet → ALB SG:   TCP 80, 443 (0.0.0.0/0)
ALB SG   → EC2 SG:   TCP 80 (ALB SG only)
EC2 SG   → RDS SG:   TCP 3306 (EC2 SG only)
EC2 SG   → VPCE SG:  TCP 443 (SSM VPC endpoints)
EC2 SG   → Outbound: TCP 80/443 (package updates, AWS APIs)
```

---

## Auto Scaling Configuration

### Policies
| Policy | Type | Trigger | Action |
|---|---|---|---|
| CPU Target Tracking | TargetTracking | CPU avg = 60% | Scale in/out automatically |
| ALB Request Count | TargetTracking | 1000 req/target | Scale in/out automatically |
| Step Scale Out | StepScaling | CPU > 80% | +1 instance; CPU > 100% → +2 |
| Step Scale In | StepScaling | CPU < 20% | -1 instance |
| Business Hours Scale Up | Scheduled | 08:00 UTC Mon-Fri | desired=4 |
| Business Hours Scale Down | Scheduled | 20:00 UTC Mon-Fri | desired=2 |

---

## CloudWatch Alarms

| Alarm | Metric | Threshold | Action |
|---|---|---|---|
| ASG High CPU | CPUUtilization (EC2) | > 70% for 2 periods | SNS alert |
| ALB Low Healthy Hosts | HealthyHostCount | < 2 | SNS alert |
| ALB High Latency | TargetResponseTime p99 | > 2s | SNS alert |
| ALB High 5xx Rate | 5xx / Total × 100 | > 5% | SNS alert |
| RDS High CPU | CPUUtilization (RDS) | > 80% | SNS alert |
| RDS Low Storage | FreeStorageSpace | < 5 GB | SNS alert |
| RDS High Connections | DatabaseConnections | > 400 | SNS alert |
| Route53 Health Check | HealthCheckStatus | < 1 | SNS alert |

---

## Prerequisites

- AWS CLI v2 configured with appropriate permissions
- An AWS account with sufficient limits (VPC, EIP, RDS, EC2)
- (Optional) An ACM certificate ARN for HTTPS
- (Optional) A registered domain name

---

## Deployment

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/project1-scalable-web-app.git
cd project1-scalable-web-app
```

### 2. Configure AWS credentials

```bash
export AWS_DEFAULT_REGION=us-east-1
aws configure   # or use aws sso login
```

### 3. Validate templates (optional but recommended)

```bash
chmod +x scripts/validate.sh
./scripts/validate.sh
```

### 4. Deploy all stacks

```bash
chmod +x scripts/deploy.sh

# Minimum required (no custom domain)
./scripts/deploy.sh \
  --email    ops@example.com \
  --db-password "YourSecurePassword123!"

# Full deployment with custom domain and HTTPS
./scripts/deploy.sh \
  --region       us-east-1 \
  --domain       example.com \
  --email        ops@example.com \
  --db-password  "YourSecurePassword123!" \
  --cert-arn     arn:aws:acm:us-east-1:123456789012:certificate/xxxx
```

### 5. Stack deployment order

The script deploys stacks in this order (each depends on exports from the previous):

```
01-vpc  →  02-security-groups  →  03-rds  →  04-alb-waf
→  05-ec2-asg  →  06-cloudfront  →  07-route53  →  08-monitoring
```

### 6. Access your application

After deployment, the script prints:
- **ALB DNS Name** — direct HTTP/HTTPS access
- **CloudFront Domain** — CDN endpoint
- **CloudWatch Dashboard URL** — monitoring

### 7. Connect to EC2 instances (no bastion required)

```bash
# List instances in the ASG
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=project1-webapp" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]" \
  --output table

# Start a Session Manager session
aws ssm start-session --target i-xxxxxxxxxxxxxxxxx
```

---

## Teardown

```bash
./scripts/teardown.sh
# You will be prompted to type the project name to confirm
```

> **Note:** The RDS instance has deletion protection enabled. The teardown script disables it automatically before deleting. A final snapshot is taken by default (`DeletionPolicy: Snapshot`).

---

## Security Highlights

| Control | Implementation |
|---|---|
| No public EC2 access | All instances in private subnets |
| No SSH/bastion | AWS Systems Manager Session Manager via VPC endpoints |
| IMDSv2 enforced | `HttpTokens: required` in Launch Template |
| Encrypted at rest | KMS CMK for RDS, EBS gp3 encrypted |
| WAF rules | OWASP Top 10, SQLi, bad inputs, IP reputation, rate limiting |
| Least-privilege IAM | EC2 role with only SSM, CWA, Secrets Manager access |
| VPC Flow Logs | All traffic logged to CloudWatch Logs (30 days) |
| Network segmentation | 3-tier subnets with NACLs and SG references |
| TLS 1.3 | ALB SSL policy `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| Security headers | CloudFront ResponseHeadersPolicy (HSTS, X-Frame, CSP) |

---

## Learning Outcomes Demonstrated

- [x] VPC with correct subnet, route table, and NAT Gateway configurations
- [x] Highly available architecture across 2 Availability Zones
- [x] ALB listener rules and target group health checks
- [x] Auto Scaling with target tracking and step scaling policies
- [x] WAF with OWASP Top 10 managed rules and rate limiting
- [x] Security Groups with source-SG references (not CIDRs)
- [x] Private subnets with no direct internet exposure
- [x] Systems Manager Session Manager as bastion-free access
- [x] CloudWatch dashboards, alarms, and SNS notifications
- [x] RDS Multi-AZ with automated failover and KMS encryption
- [x] CloudFront with S3 static assets and ALB dynamic origin
- [x] Route 53 Alias records and health checks

---

## Cost Estimates (us-east-1, on-demand)

| Resource | Monthly Estimate |
|---|---|
| 2× t3.medium EC2 | ~$60 |
| 2× NAT Gateway | ~$64 |
| db.t3.medium RDS Multi-AZ | ~$95 |
| ALB | ~$16 + data |
| CloudFront (1TB) | ~$85 |
| WAF (regional) | ~$6 |
| Route 53 Hosted Zone | ~$0.50 |
| **Total (approx.)** | **~$330/month** |

> Costs vary by traffic and region. Use [AWS Pricing Calculator](https://calculator.aws) for precise estimates.

---

## Author

Marco Essam — Cloud Infrastructure Project 1
