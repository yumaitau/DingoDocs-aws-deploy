# DingoDocs AWS Marketplace deploy

Public buyer-owned deployment artifacts for DingoDocs on AWS Marketplace. Subscribe before pulling either image or creating a deployment. DingoDocs data remains in the buyer's AWS account.

The listing supplies two immutable image references:

- application image: standalone Next.js server with built-in background jobs
- migrator image: one-shot Drizzle PostgreSQL migrations

Both images contain seller-compiled Marketplace identity and validate entitlement through AWS License Manager. Runtime environment variables cannot disable or retarget licensing. Pin published immutable tags or digests; never use `latest` or guess an image URI.

## ECS Fargate with Terraform

Terraform creates a two-AZ VPC, ALB, private ECS tasks, RDS PostgreSQL 16, KMS-encrypted S3 evidence storage, Secrets Manager, CloudWatch logging, optional WAF, and optional AWS Backup.

```sh
git clone https://github.com/yumaitau/DingoDocs-aws-deploy.git
cd DingoDocs-aws-deploy/terraform
cp terraform.tfvars.example terraform.tfvars
# Set container_image, migrator_image, and allowed_ingress_cidrs.
./bootstrap.sh -var-file=terraform.tfvars
terraform output application_url
```

The bootstrap flow creates the data plane without the web service, runs the entitlement-enforcing migrator, proves an S3 write, enables the web service, and verifies `/api/health` plus `/api/ready`. See [Terraform deployment](terraform/README.md).

## ECS Fargate with CloudFormation

CloudFormation provides the same single-NAT proof topology for console users. The initial stack intentionally leaves the web service disabled. Run the output migration task and require exit code `0`, then update `EnableWebService` to `true`.

```sh
git clone https://github.com/yumaitau/DingoDocs-aws-deploy.git
cd DingoDocs-aws-deploy/cloudformation
cp parameters.example.json parameters.json
# Set both Marketplace images and AllowedIngressCidr.
```

Upload `dingodocs-fargate.yaml` in CloudFormation or follow the complete [CloudFormation launch guide](cloudformation/README.md).

## Amazon EKS with Helm

The Helm chart does not create RDS, S3, ACM, or SES. Provision those first and attach an IRSA role with `license-manager:CheckoutLicense`, scoped S3/KMS access, and optional `ses:SendEmail`.

```sh
helm upgrade --install dingodocs charts/dingodocs \
  --namespace dingodocs --create-namespace \
  -f charts/dingodocs/values-aws-marketplace.yaml \
  --set image.repository=<marketplace-application-repository> \
  --set image.tag=<immutable-tag> \
  --set migratorImage.repository=<marketplace-migrator-repository> \
  --set migratorImage.tag=<immutable-tag> \
  --set env.APP_URL=https://dingodocs.example.com \
  --set env.BETTER_AUTH_URL=https://dingodocs.example.com \
  --set env.TRUSTED_ORIGINS=https://dingodocs.example.com \
  --set env.S3_BUCKET=<your-bucket> \
  --set existingSecret=dingodocs-runtime
```

The existing secret must contain `DATABASE_URL`, `BETTER_AUTH_SECRET`, and `INTEGRATION_ENCRYPTION_KEY`. Each Pod runs the separate migrator image as an init container; a PostgreSQL advisory lock serializes concurrent rollout migrations, and the web container cannot start until migration succeeds. See comments in [Marketplace values](charts/dingodocs/values-aws-marketplace.yaml).

## Email and first sign-in

With no SES identity, the AWS templates set `EMAIL_PROVIDER=none` and `REQUIRE_EMAIL_VERIFICATION=false`; password reset, invitations, verification, and magic-link mail are unavailable. Set `ses_from_email` / `SesFromEmail` to a verified SES identity for native task-role delivery. EKS operators set `EMAIL_PROVIDER=ses`, `EMAIL_FROM`, and `REQUIRE_EMAIL_VERIFICATION=true`.

No administrator account is seeded. The first user registers at `/sign-up`, then creates the organisation at `/onboarding`.

## Security defaults

- private application and data subnets; no public task or database address
- explicit ALB ingress CIDRs; world-open ingress requires an opt-in flag
- non-root UID/GID 1001 and all Linux capabilities dropped
- KMS encryption, S3 public-access block, versioning, access logs, and TLS-only policies
- generated application/database secrets; no static AWS access keys
- immutable application and migrator references
- fail-closed Marketplace validation before HTTP or migrations

## Cost and teardown

Buyers pay AWS for Fargate, ALB, NAT, RDS, S3, KMS, Secrets Manager, CloudWatch, and enabled WAF/Backup resources. Marketplace contract charges are separate.

Terraform teardown is guarded:

```sh
cd terraform
DINGODOCS_ALLOW_DESTROY=yes ./destroy.sh -var-file=terraform.tfvars
```

Empty retained S3 objects and preserve required database snapshots before destroying production resources.

## CI

Pushes and pull requests run Terraform formatting/validation/tests, Helm lint/rendering, CloudFormation validation, Checkov, Gitleaks, and Trivy on organisation self-hosted Linux runners.

## Support

https://github.com/yumaitau/DingoDocs/issues
