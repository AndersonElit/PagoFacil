locals {
  replication_factor  = var.number_of_broker_nodes > 1 ? 2 : 1
  min_insync_replicas = var.environment == "prod" ? 2 : 1
  log_retention_days  = var.environment == "dev" ? 7 : 30
}

# Floci orquesta un contenedor Redpanda real (compatible con la API de Kafka). El puerto
# del broker se mapea dinámicamente; obtenerlo vía GetBootstrapBrokers (output msk_bootstrap_brokers).
# Floci solo soporta CreateCluster/GetBootstrapBrokers: NO CreateConfiguration, ni logging_info,
# ni open_monitoring. En modo floci (var.floci = true) se crea el cluster con la config mínima
# (broker_node_group_info) y se omite lo demás. El SG sí se crea (floci soporta EC2 SGs) porque
# broker_node_group_info.security_groups es obligatorio en el provider. Staging/prod conservan todo.
resource "aws_security_group" "msk" {
  count       = var.enabled ? 1 : 0
  name        = "${var.project_name}-${var.environment}-msk"
  description = "Security group para el cluster MSK"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka plaintext desde la VPC"
  }

  ingress {
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka TLS desde la VPC"
  }

  ingress {
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kafka SASL/SCRAM desde la VPC"
  }

  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "ZooKeeper desde la VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "msk_broker" {
  count             = var.enabled && !var.floci ? 1 : 0
  name              = "/aws/msk/${var.project_name}-${var.environment}/broker"
  retention_in_days = local.log_retention_days

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_msk_configuration" "main" {
  count          = var.enabled && !var.floci ? 1 : 0
  name           = "${var.project_name}-${var.environment}"
  kafka_versions = [var.kafka_version]
  description    = "Configuración broker MSK para ${var.project_name} ${var.environment}"

  server_properties = <<-PROPS
auto.create.topics.enable=false
default.replication.factor=${local.replication_factor}
min.insync.replicas=${local.min_insync_replicas}
num.partitions=3
log.retention.hours=${var.environment == "dev" ? 24 : 168}
PROPS
}

resource "aws_msk_cluster" "main" {
  count                  = var.enabled ? 1 : 0
  cluster_name           = "${var.project_name}-${var.environment}"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes

  broker_node_group_info {
    # Un broker por subnet; las subnets deben estar en AZs distintas.
    instance_type   = var.broker_instance_type
    client_subnets  = slice(var.subnet_ids, 0, var.number_of_broker_nodes)
    security_groups = [aws_security_group.msk[0].id]
    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size
      }
    }
  }

  dynamic "encryption_info" {
    for_each = var.floci ? [] : [1]
    content {
      encryption_in_transit {
        client_broker = var.environment == "dev" ? "TLS_PLAINTEXT" : "TLS"
        in_cluster    = true
      }
    }
  }

  dynamic "configuration_info" {
    for_each = var.floci ? [] : [1]
    content {
      arn      = aws_msk_configuration.main[0].arn
      revision = aws_msk_configuration.main[0].latest_revision
    }
  }

  dynamic "logging_info" {
    for_each = var.floci ? [] : [1]
    content {
      broker_logs {
        cloudwatch_logs {
          enabled   = true
          log_group = aws_cloudwatch_log_group.msk_broker[0].name
        }
      }
    }
  }

  dynamic "open_monitoring" {
    for_each = var.floci ? [] : [1]
    content {
      prometheus {
        jmx_exporter { enabled_in_broker = true }
        node_exporter { enabled_in_broker = true }
      }
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Política IAM para producir/consumir desde microservicios vía autenticación IAM.
resource "aws_iam_policy" "msk_access" {
  count       = var.enabled ? 1 : 0
  name        = "${var.project_name}-${var.environment}-msk-access"
  description = "Permite a los microservicios producir y consumir en el cluster MSK"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKClusterConnect"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster"
        ]
        Resource = aws_msk_cluster.main[0].arn
      },
      {
        Sid    = "MSKTopicReadWrite"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "arn:aws:kafka:*:*:topic/${aws_msk_cluster.main[0].cluster_name}/*/*"
      },
      {
        Sid    = "MSKConsumerGroup"
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "arn:aws:kafka:*:*:group/${aws_msk_cluster.main[0].cluster_name}/*/*"
      }
    ]
  })
}
