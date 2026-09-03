# DingoDocs on AWS ECS Fargate (CloudFormation)

Native CloudFormation for buyers who do not use Terraform. The stack creates a two-AZ VPC, ALB, ECS Fargate web and migration task definitions, RDS PostgreSQL 16, Secrets Manager, KMS, and a private S3 evidence bucket.

Subscribe to DingoDocs on AWS Marketplace before creating the stack. Set `ContainerImage` to an immutable Marketplace ECR reference, not GHCR. Legacy `MigratorImage` input is ignored.

## Console

1. Open CloudFormation in the target Region.
2. Create a stack with new resources and upload `dingodocs-fargate.yaml`.
3. Pin **Marketplace application image** and **Marketplace migrator image** to published immutable listing tags or digests.
4. Set **Allowed ingress CIDR** to an office, VPN, or client range. `0.0.0.0/0` is rejected unless **Allow internet ingress** is explicitly true.
5. Leave the ACM certificate and SES From identity empty only for a restricted proof deployment.
6. Keep **Create web service** false, acknowledge IAM capabilities, and create the stack.
7. In ECS, run one task from the migration task definition output in the stack's application subnets and task security group. Continue only after its container exits `0`.
8. Update the stack, set **Create web service** true, and submit the update.

When the update is `UPDATE_COMPLETE`, open `ApplicationUrl`. The first user registers at `/sign-up` and creates the organisation at `/onboarding`; no seed administrator is included.

## CLI

```sh
cd cloudformation
cp parameters.example.json parameters.json
# Edit ContainerImage and AllowedIngressCidr. Keep EnableWebService=false.

aws cloudformation deploy \
  --stack-name dingodocs \
  --template-file dingodocs-fargate.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides $(python3 -c 'import json; print(" ".join("%s=%s" % (p["ParameterKey"], p["ParameterValue"]) for p in json.load(open("parameters.json"))))')

cluster=$(aws cloudformation describe-stacks --stack-name dingodocs --query "Stacks[0].Outputs[?OutputKey=='EcsClusterName'].OutputValue" --output text)
migration_task=$(aws cloudformation describe-stacks --stack-name dingodocs --query "Stacks[0].Outputs[?OutputKey=='MigrationTaskDefinitionArn'].OutputValue" --output text)
subnets=$(aws cloudformation describe-stacks --stack-name dingodocs --query "Stacks[0].Outputs[?OutputKey=='ApplicationSubnetIds'].OutputValue" --output text)
security_group=$(aws cloudformation describe-stacks --stack-name dingodocs --query "Stacks[0].Outputs[?OutputKey=='TaskSecurityGroupId'].OutputValue" --output text)
task_arn=$(aws ecs run-task --cluster "$cluster" --launch-type FARGATE --task-definition "$migration_task" --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$security_group],assignPublicIp=DISABLED}" --query 'tasks[0].taskArn' --output text)
aws ecs wait tasks-stopped --cluster "$cluster" --tasks "$task_arn"
test "$(aws ecs describe-tasks --cluster "$cluster" --tasks "$task_arn" --query 'tasks[0].containers[0].exitCode' --output text)" = 0

# Set EnableWebService=true in parameters.json, then update the stack.
aws cloudformation deploy \
  --stack-name dingodocs \
  --template-file dingodocs-fargate.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides $(python3 -c 'import json; print(" ".join("%s=%s" % (p["ParameterKey"], p["ParameterValue"]) for p in json.load(open("parameters.json"))))')

aws cloudformation describe-stacks --stack-name dingodocs \
  --query "Stacks[0].Outputs[?OutputKey=='ApplicationUrl'].OutputValue" \
  --output text
```

The migrator validates entitlement before changing PostgreSQL. The application validates entitlement before accepting HTTP traffic. Never enable the web service until migration exits successfully.

## Optional parameters

| Parameter | Empty/default state | Later |
| --- | --- | --- |
| `CertificateArn` + `AppUrl` | HTTP ALB | Use an ACM certificate in the ALB Region and the matching HTTPS origin. |
| `SesFromEmail` | No mail; email verification disabled | Use a verified SES identity. The task role sends through the native SES client without static keys. |
| `DatabaseMultiAz` | Off | Enable for production resilience. |
| `EnableAwsBackup` | Off | Daily AWS Backup of RDS and the evidence bucket. |
| `AllowedIngressCidr` | Required | Use an office, VPN, or client CIDR. |
| `AllowInternetIngress` | `false` | Set true only for an intentionally public deployment protected by HTTPS and WAF. |

S3 evidence storage is always created. Dual-NAT per-AZ egress is Terraform-only.

## Destroy

Empty the evidence bucket first, preserve any required database snapshot, then:

```sh
aws cloudformation delete-stack --stack-name dingodocs
aws cloudformation wait stack-delete-complete --stack-name dingodocs
```

The supplied template uses `DeletionPolicy: Delete` for proof deployments. Fork that policy before storing production data.
