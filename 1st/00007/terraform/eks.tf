resource "aws_iam_role" "eks_cluster" {
  name = "unicorn-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role" "eks_nodes" {
  name = "unicorn-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_nodes_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_launch_template" "eks_nodes_addon" {
  name_prefix = "unicorn-eks-node-addon-lt-"
  description = "Launch template for EKS Addon nodes"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "unicorn-k8snode-addon-node"
    }
  }

  user_data = base64encode(<<-EOF
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

    --==MYBOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    timedatectl set-timezone Asia/Seoul

    --==MYBOUNDARY==--
  EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "eks_nodes_app" {
  name_prefix = "unicorn-eks-node-app-lt-"
  description = "Launch template for EKS App nodes"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "unicorn-k8snode-app-node"
    }
  }

  user_data = base64encode(<<-EOF
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

    --==MYBOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    timedatectl set-timezone Asia/Seoul

    --==MYBOUNDARY==--
  EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_cluster" "main" {
  name     = "unicorn-eks-cluster"
  version  = "1.35"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = false

    security_group_ids      = [aws_security_group.eks_additional.id]
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.platform.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSVPCResourceController
  ]

  tags = {
    Name = "unicorn-eks-cluster"
  }
}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_iam_session_context.current.issuer_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.admin.principal_arn

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_node_group" "addon" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "unicorn-ng-addon"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 1
  }

  launch_template {
    id      = aws_launch_template.eks_nodes_addon.id
    version = aws_launch_template.eks_nodes_addon.latest_version
  }

  labels = {
    "unicorn" = "addon"
  }

  tags = {
    Name = "unicorn-ng-addon"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "unicorn-ng-app"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  launch_template {
    id      = aws_launch_template.eks_nodes_app.id
    version = aws_launch_template.eks_nodes_app.latest_version
  }

  labels = {
    "unicorn" = "app"
  }

  taint {
    key    = "unicorn"
    value  = "app"
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name = "unicorn-ng-app"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_nodes_AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "eks_pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_node_group.addon,
    aws_eks_node_group.app
  ]
}

resource "aws_security_group" "eks_additional" {
  name        = "unicorn-eks-addsg"
  description = "Additional security group for Unicorn EKS Cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTPS from 10.97.0.0/16"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.97.0.0/16"]
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "unicorn-eks-addsg"
  }
}
