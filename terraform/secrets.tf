resource "random_password" "better_auth" {
  length  = 48
  special = false
}

resource "random_password" "integration" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "runtime" {
  name_prefix             = "${local.name}-runtime-"
  description             = "DingoDocs runtime connection strings and application secrets"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id = aws_secretsmanager_secret.runtime.id
  secret_string = jsonencode({
    DATABASE_URL               = "postgresql://dingodocsadmin:${random_password.database.result}@${aws_db_instance.this.address}:5432/dingodocs?sslmode=require"
    BETTER_AUTH_SECRET         = random_password.better_auth.result
    INTEGRATION_ENCRYPTION_KEY = random_password.integration.result
  })
}
