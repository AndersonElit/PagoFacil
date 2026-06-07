# Floci levanta un contenedor PostgreSQL real (postgres:16-alpine) y proxya TCP a un
# puerto del host (rango 7001-7099). Floci NO soporta CreateDBSubnetGroup ni operaciones de
# red, así que en modo floci (var.floci = true) se omite el subnet group y el instance se
# crea solo con engine/credenciales. El subnet group se mantiene para staging/prod (AWS real).
resource "aws_db_subnet_group" "main" {
  count       = var.enabled && !var.floci ? 1 : 0
  name        = "${var.project_name}-${var.environment}-rds"
  description = "Subnet group para ${var.project_name} ${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "main" {
  count             = var.enabled ? 1 : 0
  identifier        = "${var.project_name}-${var.environment}"
  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_encrypted = var.environment != "dev"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = var.floci ? null : aws_db_subnet_group.main[0].name
  vpc_security_group_ids = var.vpc_security_group_ids

  multi_az            = var.multi_az
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.environment == "dev"

  backup_retention_period = var.environment == "dev" ? 0 : 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  # floci no soporta AddTagsToResource para RDS; ignorar drift en tags.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
