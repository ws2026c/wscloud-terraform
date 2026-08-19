resource "aws_kms_key" "eks_kms" {
  description             = "KMS Key for EKS Cluster and CloudWatch Logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "wsc2026-eks-kms"
  }
}

resource "aws_kms_alias" "eks_kms_alias" {
  name          = "alias/wsc2026-eks-kms"
  target_key_id = aws_kms_key.eks_kms.key_id
}

resource "aws_kms_key_policy" "eks_kms_policy" {
  key_id = aws_kms_key.eks_kms.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAdminManagement"
        Effect = "Allow"
        Principal = {
          AWS = var.admin_iam_arn
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEKSServiceAndRoleUse"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_cluster_role.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsService"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/wsc2026-eks-cluster/cluster"
          }
        }
      }
    ]
  })

  depends_on = [
    aws_iam_role.eks_cluster_role
  ]
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "wsc2026-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_security_group" "eks_additional_sg" {
  name        = "wsc2026-eks-additional-sg"
  description = "Security Group for EKS cluster allowing VPC inbound 443"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow inbound 443 HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wsc2026-eks-additional-sg"
  }
}

resource "aws_cloudwatch_log_group" "eks_log_group" {
  name              = "/aws/eks/wsc2026-eks-cluster/cluster"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.eks_kms.arn

  tags = {
    Name = "/aws/eks/wsc2026-eks-cluster/cluster"
  }

  depends_on = [
    aws_kms_key_policy.eks_kms_policy
  ]
}

resource "aws_eks_cluster" "main" {
  name     = "wsc2026-eks-cluster"
  version  = "1.35"
  role_arn = aws_iam_role.eks_cluster_role.arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = [aws_subnet.app_sub_a.id, aws_subnet.app_sub_b.id]
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_additional_sg.id]
  }

  access_config {
    authentication_mode = "API"
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_kms.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks_log_group,
    aws_kms_key_policy.eks_kms_policy
  ]

  tags = {
    Name = "wsc2026-eks-cluster"
  }
}

resource "aws_eks_access_entry" "admin_access_entry" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.admin_iam_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin_policy_assoc" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.admin_iam_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin_access_entry]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

#resource "aws_eks_addon" "coredns" {
#  cluster_name = aws_eks_cluster.main.name
#  addon_name   = "coredns"
#
#  depends_on = [aws_eks_addon.vpc_cni]
#}