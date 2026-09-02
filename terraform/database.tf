resource "random_password" "database" {
  length  = 40
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-database"
  subnet_ids = aws_subnet.data[*].id

  tags = {
    Name = "${local.name}-database"
  }
}

resource "aws_db_instance" "this" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.database_instance_class

  db_name  = "dingodocs"
  username = "dingodocsadmin"
  password = random_password.database.result
  port     = 5432

  allocated_storage     = var.database_allocated_storage
  max_allocated_storage = var.database_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = var.database_multi_az

  backup_retention_period         = var.database_backup_retention_days
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  apply_immediately               = true
  deletion_protection             = var.database_deletion_protection
  skip_final_snapshot             = var.skip_final_database_snapshot
  final_snapshot_identifier       = var.skip_final_database_snapshot ? null : "${local.name}-final"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name = "${local.name}-postgres"
  }
}
