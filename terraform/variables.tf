variable "aws_region" {
  type        = string
  description = "AWS region for every resource."
  default     = "ap-southeast-2"

  validation {
    condition     = contains(["ap-southeast-2", "us-east-1"], var.aws_region)
    error_message = "Supported regions are ap-southeast-2 (default) and us-east-1 (AWS Marketplace metering proof)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Short prefix used for AWS resource names."
  default     = "dingodocs"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.name_prefix))
    error_message = "name_prefix must be 2-16 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "test"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.environment))
    error_message = "environment must be 2-16 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "cpu_architecture" {
  type        = string
  description = "Fargate CPU architecture. X86_64 is the listing default. ARM64 is valid when the image has a linux/arm64 variant."
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "container_image" {
  type        = string
  description = "DingoDocs OCI image pinned to a digest or immutable version tag. Floating tags are rejected."

  validation {
    condition = (
      can(regex("(@sha256:[0-9a-f]{64}|:[A-Za-z0-9][A-Za-z0-9_.-]{0,127})$", var.container_image)) &&
      !can(regex(":[Ll][Aa][Tt][Ee][Ss][Tt]$", var.container_image))
    )
    error_message = "container_image must end in an immutable tag or sha256 digest; floating tags are not allowed."
  }
}

variable "migrator_image" {
  type        = string
  description = "Deprecated compatibility input. Ignored; the migration task always uses container_image."
  default     = "unused:compat"

  validation {
    condition = (
      can(regex("(@sha256:[0-9a-f]{64}|:[A-Za-z0-9][A-Za-z0-9_.-]{0,127})$", var.migrator_image)) &&
      !can(regex(":[Ll][Aa][Tt][Ee][Ss][Tt]$", var.migrator_image))
    )
    error_message = "migrator_image must end in an immutable tag or sha256 digest; floating tags are not allowed."
  }
}

variable "container_registry_credentials_secret_arn" {
  type        = string
  description = "Optional Secrets Manager ARN containing private registry credentials as {username,password}. Omit when container_image is an AWS Marketplace ECR URI."
  default     = null
  nullable    = true
}

variable "ses_from_email" {
  type        = string
  description = "Verified Amazon SES From identity (e.g. DingoDocs <no-reply@example.com>). Empty disables outbound email. Uses the ECS task role, not SMTP keys."
  default     = ""
}

variable "app_url" {
  type        = string
  description = "Canonical public URL. Null uses the ALB URL. Set this with certificate_arn for production."
  default     = null
  nullable    = true

  validation {
    condition     = var.app_url == null || can(regex("^https?://[^/]+/?$", var.app_url))
    error_message = "app_url must be an absolute HTTP(S) origin without a path."
  }
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS. Null enables HTTP for short-lived test deployments only."
  default     = null
  nullable    = true
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the DingoDocs VPC."
  default     = "10.80.0.0/16"
}

variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "IPv4 CIDRs allowed to reach the ALB. Required. 0.0.0.0/0 is rejected unless allow_internet_ingress is true."

  validation {
    condition     = length(var.allowed_ingress_cidrs) > 0 && alltrue([for cidr in var.allowed_ingress_cidrs : can(cidrhost(cidr, 0))])
    error_message = "allowed_ingress_cidrs must contain at least one valid IPv4 CIDR."
  }
}

variable "allow_internet_ingress" {
  type        = bool
  description = "Permit 0.0.0.0/0 on the ALB. Off by default. Use only for a public service behind WAF and HTTPS."
  default     = false
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use one NAT gateway to reduce test cost. Set false for AZ-resilient production egress."
  default     = true
}

variable "use_nat_gateway" {
  type        = bool
  description = "Keep Fargate tasks in private application subnets behind NAT. Disable only when NAT is unavailable or unnecessary; tasks then receive public egress IPs but accept inbound traffic only from the ALB security group."
  default     = true
}

variable "enable_services" {
  type        = bool
  description = "Create the web service. Bootstrap keeps this false until migration succeeds."
  default     = true
}

variable "web_desired_count" {
  type        = number
  description = "Number of web tasks."
  default     = 1

  validation {
    condition     = var.web_desired_count >= 1
    error_message = "web_desired_count must be at least 1."
  }
}

variable "web_cpu" {
  type        = number
  description = "Web task CPU units."
  default     = 1024
}

variable "web_memory" {
  type        = number
  description = "Web task memory in MiB."
  default     = 2048
}

variable "migration_cpu" {
  type        = number
  description = "Migration task CPU units."
  default     = 512
}

variable "migration_memory" {
  type        = number
  description = "Migration task memory in MiB."
  default     = 1024
}

variable "database_instance_class" {
  type        = string
  description = "RDS PostgreSQL instance class."
  default     = "db.t4g.micro"
}

variable "database_allocated_storage" {
  type        = number
  description = "Initial RDS gp3 storage in GiB."
  default     = 20
}

variable "database_max_allocated_storage" {
  type        = number
  description = "RDS autoscaling storage ceiling in GiB."
  default     = 100
}

variable "database_multi_az" {
  type        = bool
  description = "Create a Multi-AZ RDS instance. Enable for production."
  default     = false
}

variable "database_deletion_protection" {
  type        = bool
  description = "Protect RDS from deletion. Enable for production; disable before intentional destroy."
  default     = false
}

variable "skip_final_database_snapshot" {
  type        = bool
  description = "Skip final RDS snapshot on destroy. True keeps test teardown deterministic."
  default     = true
}

variable "database_backup_retention_days" {
  type        = number
  description = "RDS automated backup retention."
  default     = 7
}

variable "enable_waf" {
  type        = bool
  description = "Associate an AWS managed-rule WAFv2 ACL with the ALB."
  default     = true
}

variable "enable_aws_backup" {
  type        = bool
  description = "Protect RDS through AWS Backup in addition to native retention."
  default     = false
}

variable "backup_retention_days" {
  type        = number
  description = "AWS Backup recovery point retention."
  default     = 35
}

variable "force_destroy_backup_vault" {
  type        = bool
  description = "Delete recovery points with the vault during destroy. True is suitable only for test accounts."
  default     = true
}

variable "force_destroy_evidence_bucket" {
  type        = bool
  description = "Allow Terraform to delete evidence objects during destroy. True is suitable only for test accounts."
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention."
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Extra tags applied through provider default tags."
  default     = {}
}
