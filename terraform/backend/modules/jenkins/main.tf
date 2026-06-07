data "aws_caller_identity" "current" {}

locals {
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# --- Security Groups ---

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-jenkins-alb"
  description = "Security group para el ALB de Jenkins"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
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

resource "aws_security_group" "jenkins_ec2" {
  name        = "${var.project_name}-${var.environment}-jenkins-ec2"
  description = "Security group para la instancia EC2 del controller Jenkins"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "UI Jenkins desde ALB"
  }

  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Agentes JNLP"
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

# --- EBS (persistencia de JENKINS_HOME) ---
# La AZ del volumen se deriva de subnet_ids[0] para coincidir con la instancia EC2.

data "aws_subnet" "jenkins_primary" {
  count = var.availability_zone == "" ? 1 : 0
  id    = var.subnet_ids[0]
}

locals {
  jenkins_az = var.availability_zone != "" ? var.availability_zone : data.aws_subnet.jenkins_primary[0].availability_zone
}

resource "aws_ebs_volume" "jenkins_home" {
  availability_zone = local.jenkins_az
  size              = var.volume_size_gb
  type              = var.volume_type
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-jenkins-home"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle {
    prevent_destroy = true
  }
}

# --- IAM para la instancia EC2 del controller ---

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins_ec2" {
  name               = "${var.project_name}-${var.environment}-jenkins-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Permite a SSM administrar la instancia (sesiones sin SSH abierto).
# attach_ssm_policy = false en Floci: AmazonSSMManagedInstanceCore no existe.
resource "aws_iam_role_policy_attachment" "jenkins_ec2_ssm" {
  count      = var.attach_ssm_policy ? 1 : 0
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "jenkins_ec2" {
  name        = "${var.project_name}-${var.environment}-jenkins-ec2"
  description = "Adjuntar el EBS de JENKINS_HOME y resolver el cluster EKS (kubeconfig)"

  lifecycle {
    ignore_changes = [description, tags_all]
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AttachJenkinsHome"
        Effect   = "Allow"
        Action   = ["ec2:AttachVolume", "ec2:DescribeVolumes", "ec2:DescribeVolumeStatus"]
        Resource = "*"
      },
      {
        # El Kubernetes plugin usa esta identidad para 'aws eks get-token' y
        # lanzar los pods agente; el acceso RBAC lo concede el access entry.
        Sid      = "DescribeEksCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ec2" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = aws_iam_policy.jenkins_ec2.arn
}

resource "aws_iam_instance_profile" "jenkins_ec2" {
  name = "${var.project_name}-${var.environment}-jenkins-ec2"
  role = aws_iam_role.jenkins_ec2.name
}

# --- IAM IRSA para los pods agente (ServiceAccount jenkins-agent) ---
# Federación OIDC del cluster EKS: solo el SA jenkins:jenkins-agent puede asumir
# este rol. kaniko lo usa para push a ECR; el deploy para 'aws eks get-token'.

data "aws_iam_policy_document" "jenkins_agent_assume_role" {
  count = var.enable_compute ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${var.agent_namespace}:jenkins-agent"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins_agent" {
  count              = var.enable_compute ? 1 : 0
  name               = "${var.project_name}-${var.environment}-jenkins-agent"
  assume_role_policy = data.aws_iam_policy_document.jenkins_agent_assume_role[0].json
}

resource "aws_iam_policy" "jenkins_agent" {
  count       = var.enable_compute ? 1 : 0
  name        = "${var.project_name}-${var.environment}-jenkins-agent"
  description = "Permisos del agente: push/pull ECR (kaniko), leer secrets y describir EKS (deploy)"

  lifecycle {
    ignore_changes = [description, tags_all]
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      },
      {
        # Necesario para 'aws eks update-kubeconfig' antes de helm/kubectl;
        # el acceso RBAC al namespace lo concede el access entry del agente.
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_agent" {
  count      = var.enable_compute ? 1 : 0
  role       = aws_iam_role.jenkins_agent[0].name
  policy_arn = aws_iam_policy.jenkins_agent[0].arn
}

# --- EKS access entries (RBAC vía identidad AWS) ---
# Floci no soporta CreateAccessEntry; en dev se desactivan con enable_compute = false.
# Controller: crea/borra los pods agente en el namespace 'jenkins'.
resource "aws_eks_access_entry" "jenkins_controller" {
  count         = var.enable_compute ? 1 : 0
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.jenkins_ec2.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "jenkins_controller" {
  count         = var.enable_compute ? 1 : 0
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.jenkins_ec2.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.agent_namespace]
  }

  depends_on = [aws_eks_access_entry.jenkins_controller]
}

# Agente: despliega (helm/kubectl) en el namespace de la aplicación del ambiente.
resource "aws_eks_access_entry" "jenkins_agent" {
  count         = var.enable_compute ? 1 : 0
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.jenkins_agent[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "jenkins_agent" {
  count         = var.enable_compute ? 1 : 0
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.jenkins_agent[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.environment]
  }

  depends_on = [aws_eks_access_entry.jenkins_agent]
}

# --- Launch Template + ASG (instancia EC2 singleton del controller) ---
# Floci no soporta CreateLaunchTemplate; en dev se desactiva con enable_compute = false.

resource "aws_launch_template" "jenkins" {
  count         = var.enable_compute ? 1 : 0
  name_prefix   = "${var.project_name}-${var.environment}-jenkins-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.jenkins_ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.jenkins_ec2.id]
  }

  # $INSTANCE_ID/$REGION/$DEVICE/$i/$PRIVATE_IP son variables bash (runtime en EC2).
  # ${...} son interpolaciones Terraform expandidas en apply time.
  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    # --- Herramientas: Docker, aws-cli v2, kubectl ---
    if command -v dnf &>/dev/null; then
      dnf install -y docker unzip
    else
      amazon-linux-extras install -y docker && yum install -y unzip
    fi
    systemctl enable --now docker

    if ! command -v aws &>/dev/null; then
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install
    fi

    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl

    # --- Adjuntar y montar el EBS de JENKINS_HOME ---
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    VOLUME_ID="${aws_ebs_volume.jenkins_home.id}"

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

    if ! blkid "$DEVICE" &>/dev/null; then
      mkfs -t ext4 "$DEVICE"
    fi

    mkdir -p /var/jenkins_home
    mount "$DEVICE" /var/jenkins_home
    grep -q /var/jenkins_home /etc/fstab || \
      echo "$DEVICE /var/jenkins_home ext4 defaults,nofail 0 2" >> /etc/fstab

    # --- kubeconfig para el Kubernetes plugin (exec auth vía rol de la EC2) ---
    mkdir -p /var/jenkins_home/.kube
    aws eks update-kubeconfig \
      --name "${var.eks_cluster_name}" \
      --region "$REGION" \
      --kubeconfig /var/jenkins_home/.kube/config
    chown -R 1000:1000 /var/jenkins_home

    # --- Arrancar el controller Jenkins ---
    # var.jenkins_image deberia ser la imagen propia con JCasC + plugins horneados
    # (jenkins-shared-library/docker). Las variables de entorno alimentan las
    # interpolaciones del jenkins.yaml (JCasC).
    docker run -d --name jenkins --restart unless-stopped \
      -p 8080:8080 -p 50000:50000 \
      -v /var/jenkins_home:/var/jenkins_home \
      -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
      -e ECR_REGISTRY="${local.ecr_registry}" \
      -e EKS_CLUSTER_NAME="${var.eks_cluster_name}" \
      -e EKS_API_SERVER="${var.eks_cluster_endpoint}" \
      -e AWS_REGION="$REGION" \
      -e JENKINS_URL="http://$PRIVATE_IP:8080" \
      -e JENKINS_TUNNEL="$PRIVATE_IP:50000" \
      -e SHARED_LIBRARY_REPO="${var.shared_library_repo}" \
      -e SONAR_URL="${var.sonar_url}" \
      -e SONAR_TOKEN="${var.sonar_token}" \
      -e SLACK_TEAM="${var.slack_team}" \
      -e SLACK_TOKEN="${var.slack_token}" \
      -e VERCEL_TOKEN="${var.vercel_token}" \
      -e VERCEL_ORG_ID="${var.vercel_org_id}" \
      -e VERCEL_PROJECT_ID="${var.vercel_project_id}" \
      -e GITOPS_GIT_USERNAME="${var.gitops_git_username}" \
      -e GITOPS_GIT_TOKEN="${var.gitops_git_token}" \
      "${var.jenkins_image}"
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-jenkins"
      Environment = var.environment
      Project     = var.project_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Singleton: desired/min/max = 1. Fijado a subnet_ids[0] para que la AZ
# coincida con el volumen EBS.
resource "aws_autoscaling_group" "jenkins" {
  count               = var.enable_compute ? 1 : 0
  name                = "${var.project_name}-${var.environment}-jenkins"
  vpc_zone_identifier = [var.subnet_ids[0]]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 1

  launch_template {
    id      = aws_launch_template.jenkins[0].id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
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

# --- ALB ---
# Floci no enruta ELBv2; en dev se desactiva con enable_compute = false.

resource "aws_lb" "jenkins" {
  count              = var.enable_compute ? 1 : 0
  name               = "${var.project_name}-${var.environment}-jenkins"
  internal           = var.alb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group" "jenkins" {
  count       = var.enable_compute ? 1 : 0
  name        = "${var.project_name}-${var.environment}-jenkins"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/login"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "jenkins" {
  count             = var.enable_compute ? 1 : 0
  load_balancer_arn = aws_lb.jenkins[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins[0].arn
  }
}

# Registra el ASG como target del ALB (target_type = instance).
resource "aws_autoscaling_attachment" "jenkins" {
  count                  = var.enable_compute ? 1 : 0
  autoscaling_group_name = aws_autoscaling_group.jenkins[0].name
  lb_target_group_arn    = aws_lb_target_group.jenkins[0].arn
}
