resource "aws_launch_template" "node_lt" {
  name_prefix = "o11y-node-lt-"

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

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "o11y-node"
    }
  }
}

resource "aws_eks_cluster" "cluster" {
  name     = "o11y-cluster"
  role_arn = aws_iam_role.cluster_role.arn
  version  = "1.35"

  vpc_config {
    subnet_ids              = [aws_subnet.priv_a.id, aws_subnet.priv_c.id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.cluster.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.cluster.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.cluster.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.nodegroup]
}

resource "aws_eks_node_group" "nodegroup" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "o11y-nodegroup"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = [aws_subnet.priv_a.id, aws_subnet.priv_c.id]

  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  launch_template {
    id      = aws_launch_template.node_lt.id
    version = aws_launch_template.node_lt.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}
