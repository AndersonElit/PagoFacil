data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "nodes_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project_name}-${var.environment}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count      = var.attach_managed_policies ? 1 : 0
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "nodes" {
  name               = "${var.project_name}-${var.environment}-eks-nodes"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume_role.json
}

resource "aws_iam_role_policy_attachment" "nodes_worker" {
  count      = var.attach_managed_policies ? 1 : 0
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "nodes_cni" {
  count      = var.attach_managed_policies ? 1 : 0
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "nodes_ecr" {
  count      = var.attach_managed_policies ? 1 : 0
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  # Habilita EKS access entries (RBAC vía identidad IAM) además del aws-auth
  # ConfigMap. Necesario para los access entries del controller/agente Jenkins.
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  # floci no soporta UpdateClusterConfig; ignorar drift en access_config.
  lifecycle {
    ignore_changes = [access_config]
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# --- OIDC provider (IRSA) ---
# Permite que los ServiceAccounts del cluster (p. ej. jenkins-agent) asuman
# roles IAM mediante web identity federation.
# Floci no popula identity[0].oidc[0] ni soporta node groups; en dev se desactiva
# el data plane con enable_data_plane = false.
data "tls_certificate" "oidc" {
  count = var.enable_data_plane ? 1 : 0
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "main" {
  count           = var.enable_data_plane ? 1 : 0
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc[0].certificates[0].sha1_fingerprint]

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_eks_node_group" "main" {
  count           = var.enable_data_plane ? 1 : 0
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-ng"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.nodes_worker,
    aws_iam_role_policy_attachment.nodes_cni,
    aws_iam_role_policy_attachment.nodes_ecr,
  ]
}
