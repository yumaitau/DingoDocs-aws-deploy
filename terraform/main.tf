provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Application = "DingoDocs"
        Environment = var.environment
        ManagedBy   = "Terraform"
      },
      var.tags,
    )
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.name_prefix}-${var.environment}"
  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2,
  )

  # Known at plan time so terraform test can assert these without decoding
  # container_definitions (that JSON includes computed secret ARNs and URLs).
  container_hardening = {
    user       = "1001:1001"
    privileged = false
    linuxParameters = {
      capabilities = {
        drop = ["ALL"]
      }
    }
  }

  application_scheme = var.certificate_arn == null ? "http" : "https"
  application_url = coalesce(
    var.app_url,
    "${local.application_scheme}://${aws_lb.web.dns_name}",
  )

  common_environment = [
    { name = "NODE_ENV", value = "production" },
    { name = "HOSTNAME", value = "0.0.0.0" },
    { name = "NEXT_TELEMETRY_DISABLED", value = "1" },
    { name = "APP_URL", value = local.application_url },
    { name = "BETTER_AUTH_URL", value = local.application_url },
    { name = "TRUSTED_ORIGINS", value = local.application_url },
    { name = "REQUIRE_EMAIL_VERIFICATION", value = var.ses_from_email == "" ? "false" : "true" },
    { name = "EMAIL_PROVIDER", value = var.ses_from_email == "" ? "none" : "ses" },
    { name = "STORAGE_PROVIDER", value = "s3" },
    { name = "S3_BUCKET", value = aws_s3_bucket.evidence.id },
    { name = "S3_REGION", value = var.aws_region },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "CRON_TIMEZONE", value = "Australia/Sydney" },
  ]

  ses_environment = var.ses_from_email == "" ? [] : [
    { name = "EMAIL_FROM", value = var.ses_from_email },
    { name = "SES_REGION", value = var.aws_region },
  ]

  common_secrets = [
    for key in [
      "DATABASE_URL",
      "BETTER_AUTH_SECRET",
      "INTEGRATION_ENCRYPTION_KEY",
      ] : {
      name      = key
      valueFrom = "${aws_secretsmanager_secret.runtime.arn}:${key}::"
    }
  ]

  alb_ingress_rules = {
    for pair in setproduct(
      var.certificate_arn == null ? [80] : [80, 443],
      var.allowed_ingress_cidrs,
      ) : "${pair[0]}-${replace(pair[1], "/", "-")}" => {
      port = pair[0]
      cidr = pair[1]
    }
  }
}
