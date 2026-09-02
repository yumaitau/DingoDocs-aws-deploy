# DingoDocs on AWS ECS Fargate

Buyer launch path: clone https://github.com/yumaitau/DingoDocs-aws-deploy and start from the repository README. Subscribe on the DingoDocs AWS Marketplace listing before `terraform apply`.

Terraform reference stack for a buyer-owned deployment in `ap-southeast-2`:

- Two-AZ VPC with public ALB subnets, private Fargate subnets, isolated data subnets, NAT egress, and an S3 gateway endpoint.
- ECS Fargate `X86_64` task definitions for the web service and one-shot migrator.
- RDS PostgreSQL 16 with no public route or public address.
- KMS-encrypted, versioned, public-blocked S3 evidence bucket.
- Secrets Manager runtime secret, ECS execution role, and least-privilege S3 task role. No AWS access keys enter task definitions.
- CloudWatch logs and Container Insights, ALB readiness checks, optional WAF, and optional AWS Backup.

Amazon EKS buyers use the same Marketplace image via `../charts/dingodocs` and `../charts/dingodocs/values-aws-marketplace.yaml`.

## Prerequisites

- Terraform 1.8 or newer.
- AWS CLI authenticated to the intended account.
- `jq` and `curl` for `bootstrap.sh`.
- Immutable DingoDocs application and migrator images containing `linux/amd64`.
- AWS Marketplace buyers: set `container_image` and `migrator_image` to existing Marketplace ECR digests. No GitHub token. Licensing is enforced by both images.
- Private GHCR only: existing Secrets Manager secret containing exactly `{"username":"...","password":"..."}`. Password must be a GitHub token with `read:packages`.

Never put secrets in `terraform.tfvars`, shell history, or committed files. Terraform state contains generated database/application secrets; use an encrypted remote backend with restricted access for production.

NAT egress is the default. Accounts without spare Elastic IP quota can set
`use_nat_gateway = false`. Fargate tasks then receive public egress IPs in the
application subnets, while their security group still accepts inbound port
3000 only from the ALB security group. RDS remains isolated and private.

## Clean-account deployment

The stack creates Secrets Manager, RDS, and S3. First visitor registers at
`/sign-up` and creates the organisation at `/onboarding`; no seed administrator
is baked into the image. Leave `ses_from_email` empty for a temporary install
without email verification, or set it to a verified SES identity before launch.

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Pin both images to Marketplace ECR digests. Do not set a GHCR pull secret.
./bootstrap.sh -var-file=terraform.tfvars
terraform output application_url
```

`bootstrap.sh` is the required first-launch path. It creates the data plane with
services off, runs the entitlement-enforcing migrator, proves an S3 write, then
creates the web service and verifies `/api/health` plus `/api/ready`. Evidence is
written to `terraform/evidence/aws-fargate-deploy.md`.

Use `terraform plan` / `terraform apply` for later infrastructure changes that
do not change the application schema. For upgrades, back up PostgreSQL and S3,
run the new migrator task successfully, then update the web image.

## Outputs

```sh
terraform output application_url
terraform output web_task_definition_arn
terraform output migration_task_definition_arn
terraform output evidence_bucket_name
```

Outputs never contain secret values.

## Required vs optional AWS services

This stack always creates the services DingoDocs needs to boot:

- VPC, NAT, ALB, ECS Fargate web service and migration task definition
- RDS PostgreSQL 16
- KMS-encrypted S3 evidence bucket + S3 gateway endpoint
- Secrets Manager, CloudWatch logs
- ECS execution role + task role with S3/KMS and License Manager checkout, extension, and check-in permissions

S3 is not a later add-on. Evidence uploads use this bucket. Do not tell operators to invent a second IAM role “for TLS in front of the instance”. TLS is an ACM certificate on the ALB (or their own proxy). IAM for S3/SES/License Manager already lives on the ECS **task** role.

Leave these unset until the buyer chooses them. First `/sign-up` works without either:

| Choice | Terraform | What happens if empty |
| --- | --- | --- |
| HTTPS | `certificate_arn` + `app_url` | HTTP ALB. Suitable only for a restricted proof run. |
| Outbound email | `ses_from_email` (verified SES identity) | Email verification is disabled; password reset, invitations, verification, and magic-link messages are unavailable. |

Amazon EKS buyers do **not** get RDS or S3 from this module. They provision those plus IRSA themselves (`../charts/dingodocs/values-aws-marketplace.yaml`).

## Production switches

Test defaults optimise for a short proof run. Production should set:

```hcl
app_url                       = "https://dingodocs.example.com"
certificate_arn                = "arn:aws:acm:ap-southeast-2:...:certificate/..."
allowed_ingress_cidrs          = ["203.0.113.0/24"]
allow_internet_ingress         = false
database_multi_az              = true
database_deletion_protection   = true
single_nat_gateway             = false
use_nat_gateway                = true
enable_aws_backup              = true
force_destroy_backup_vault     = false
force_destroy_evidence_bucket  = false
```

`allowed_ingress_cidrs` is required. `0.0.0.0/0` is rejected unless `allow_internet_ingress = true`. Use that flag only for a public site behind WAF and HTTPS.

HTTPS is ACM on the ALB. Request the certificate in the same Region as the load balancer, then set both `certificate_arn` and `app_url`. Same `terraform apply` later; no new IAM role.

Outbound email is optional and should wait until the first admin exists (so signup is not gated on mail that never arrives):

```hcl
ses_from_email = "DingoDocs <no-reply@example.com>"
```

That identity must already be verified in Amazon SES. The stack then sets `EMAIL_PROVIDER=ses` and adds `ses:SendEmail` on the existing task role. The application uses the ECS task role; no static AWS or SMTP credentials are stored.

Configure DNS to the ALB, use a remote state backend, and set a final-snapshot policy appropriate to the buyer. Do not ship `0.0.0.0/0` on the ALB unless `allow_internet_ingress` is an explicit, reviewed decision.

## Destroy

Test stack destroy is guarded and uses the same variable arguments as bootstrap:

```sh
DINGODOCS_ALLOW_DESTROY=yes ./destroy.sh -var-file=terraform.tfvars
```

`database_deletion_protection=true`, `force_destroy_backup_vault=false`, and `force_destroy_evidence_bucket=false` intentionally block destructive production teardown. Disable protection only after approved backup/export, retained recovery points, and evidence disposition. Test defaults skip the final RDS snapshot and allow test evidence/recovery-point deletion so ALB, NAT, and RDS costs do not linger.
