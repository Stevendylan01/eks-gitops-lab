terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "aws_region" {
  description = "AWS region for the ECR repository."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the account's existing GitHub Actions OIDC provider, if present."
  type        = string
  default     = null
}

provider "aws" {
  region = var.aws_region
}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  github_subject   = "repo:Stevendylan01@20880936/go-node-info@1464501791:ref:refs/heads/main"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_provider_arn == null ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_ecr_repository" "app" {
  name = "go-node-info"
}

resource "aws_iam_role" "github_publish" {
  name = "go-node-info-github-publish"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn : one(aws_iam_openid_connect_provider.github[*].arn)
      }
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub" = local.github_subject
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.github_publish.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.app.arn
      },
    ]
  })
}

output "github_actions_variables" {
  description = "Repository variables for the go-node-info publishing workflow."
  value = {
    AWS_ROLE_ARN   = aws_iam_role.github_publish.arn
    AWS_REGION     = var.aws_region
    ECR_REPOSITORY = aws_ecr_repository.app.name
  }
}
