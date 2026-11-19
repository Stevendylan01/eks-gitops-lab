variable "eks_operator_trusted_principal_arn" {
  description = "IAM user or role allowed to assume the lab's EKS operator role."
  type        = string
  default     = "arn:aws:iam::352243450529:user/AdminUser"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_role" "eks_operator" {
  name = "eks-gitops-lab-operator"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = var.eks_operator_trusted_principal_arn }
    }]
  })
}

resource "aws_iam_role_policy" "eks_operator" {
  name = "describe-lab-cluster"
  role = aws_iam_role.eks_operator.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/eks-gitops-lab"
    }]
  })
}

output "eks_operator_role_arn" {
  description = "IAM role ARN for the EKS Terraform root's cluster admin access entry."
  value       = aws_iam_role.eks_operator.arn
}
