# --- Security Group ---
# Puerto 27017 accesible solo desde la VPC; la SG es el control de acceso.

resource "aws_security_group" "mongodb" {
  name        = "${var.project_name}-${var.environment}-mongodb"
  description = "Security group para la instancia EC2 de MongoDB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "MongoDB desde la VPC"
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

# --- EBS (datos de MongoDB en /var/lib/mongodb) ---
# La AZ se deriva de subnet_ids[0] para que coincida con la instancia EC2.

data "aws_subnet" "mongodb_primary" {
  count = var.availability_zone == "" ? 1 : 0
  id    = var.subnet_ids[0]
}

locals {
  mongodb_az = var.availability_zone != "" ? var.availability_zone : data.aws_subnet.mongodb_primary[0].availability_zone
}

resource "aws_ebs_volume" "mongodb_data" {
  availability_zone = local.mongodb_az
  size              = var.volume_size_gb
  type              = var.volume_type
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-mongodb-data"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

# --- Credenciales en Secrets Manager ---

resource "aws_secretsmanager_secret" "mongodb_admin" {
  name        = "/${var.environment}/mongodb/admin"
  description = "Credenciales del usuario admin de MongoDB"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "mongodb_admin" {
  secret_id = aws_secretsmanager_secret.mongodb_admin.id
  secret_string = jsonencode({
    username = "admin"
    password = var.mongodb_admin_password
  })
}

# --- IAM ---

data "aws_iam_policy_document" "mongodb_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mongodb_ec2" {
  name               = "${var.project_name}-${var.environment}-mongodb-ec2"
  assume_role_policy = data.aws_iam_policy_document.mongodb_assume_role.json
}

# SSM Session Manager para acceso operacional sin SSH
resource "aws_iam_role_policy_attachment" "mongodb_ssm" {
  role       = aws_iam_role.mongodb_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "mongodb_ec2" {
  name        = "${var.project_name}-${var.environment}-mongodb-ec2"
  description = "Permite adjuntar EBS, leer credenciales y escribir logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EBSAttach"
        Effect   = "Allow"
        Action   = ["ec2:AttachVolume", "ec2:DescribeVolumes", "ec2:DescribeVolumeStatus"]
        Resource = "*"
      },
      {
        Sid      = "SecretsRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.mongodb_admin.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.mongodb.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mongodb_ec2" {
  role       = aws_iam_role.mongodb_ec2.name
  policy_arn = aws_iam_policy.mongodb_ec2.arn
}

resource "aws_iam_instance_profile" "mongodb_ec2" {
  name = "${var.project_name}-${var.environment}-mongodb-ec2"
  role = aws_iam_role.mongodb_ec2.name
}

# --- CloudWatch Log Group ---

resource "aws_cloudwatch_log_group" "mongodb" {
  name              = "/ec2/${var.project_name}-${var.environment}-mongodb"
  retention_in_days = 30

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Launch Template + ASG (instancia EC2 singleton) ---

resource "aws_launch_template" "mongodb" {
  name_prefix   = "${var.project_name}-${var.environment}-mongodb-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.mongodb_ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.mongodb.id]
  }

  # Terraform expande ${...} en apply time; $VAR (sin llaves) queda como variable bash.
  # ${aws_ebs_volume.mongodb_data.id}          → ID del volumen al aplicar Terraform
  # ${aws_secretsmanager_secret.mongodb_admin.arn} → ARN del secret al aplicar Terraform
  # ${var.mongodb_version} dentro de << 'REPO' → versión inyectada por Terraform
  # $INSTANCE_ID, $REGION, $DEVICE, etc.       → variables bash expandidas en runtime EC2
  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -euo pipefail

    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    VOLUME_ID="${aws_ebs_volume.mongodb_data.id}"
    SECRET_ARN="${aws_secretsmanager_secret.mongodb_admin.arn}"

    # --- Adjuntar y montar volumen EBS ---
    aws ec2 attach-volume \
      --volume-id "$VOLUME_ID" \
      --instance-id "$INSTANCE_ID" \
      --device /dev/xvdf \
      --region "$REGION"

    for i in $(seq 1 30); do
      { [ -e /dev/xvdf ] || [ -e /dev/nvme1n1 ]; } && break
      sleep 2
    done

    DEVICE=$([ -e /dev/nvme1n1 ] && echo /dev/nvme1n1 || echo /dev/xvdf)
    IS_NEW=0

    if ! blkid "$DEVICE" &>/dev/null; then
      mkfs -t xfs "$DEVICE"
      IS_NEW=1
    fi

    mkdir -p /var/lib/mongodb
    mount "$DEVICE" /var/lib/mongodb
    echo "$DEVICE /var/lib/mongodb xfs defaults,nofail 0 2" >> /etc/fstab

    # --- Instalar MongoDB ${var.mongodb_version} ---
    cat > /etc/yum.repos.d/mongodb-org.repo << 'REPO'
[mongodb-org-${var.mongodb_version}]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/${var.mongodb_version}/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-${var.mongodb_version}.asc
REPO

    yum install -y mongodb-org

    # --- Configurar mongod.conf ---
    chown -R mongod:mongod /var/lib/mongodb

    cat > /etc/mongod.conf << 'MONGOCFG'
storage:
  dbPath: /var/lib/mongodb
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
MONGOCFG

    systemctl enable mongod
    systemctl start mongod

    # --- Crear usuario admin (solo primer arranque, volumen nuevo) ---
    if [ "$IS_NEW" -eq 1 ]; then
      sleep 5
      ADMIN_PASS=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_ARN" \
        --region "$REGION" \
        --query SecretString \
        --output text | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

      mongosh --quiet admin --eval "
        db.createUser({
          user: 'admin',
          pwd: '$ADMIN_PASS',
          roles: [{ role: 'root', db: 'admin' }]
        })
      "
    fi
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-mongodb"
      Environment = var.environment
      Project     = var.project_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Singleton: desired/min/max = 1, fijado a la AZ del volumen EBS.
resource "aws_autoscaling_group" "mongodb" {
  name                = "${var.project_name}-${var.environment}-mongodb"
  vpc_zone_identifier = [var.subnet_ids[0]]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 1

  launch_template {
    id      = aws_launch_template.mongodb.id
    version = "$Latest"
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
