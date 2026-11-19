variable "aws_region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Two distinct Availability Zones in the selected region."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(distinct(var.availability_zones)) == 2 && length(var.availability_zones) == 2
    error_message = "Specify exactly two distinct Availability Zones."
  }
}

variable "public_api_cidr" {
  description = "Operator's public IPv4 address in /32 CIDR notation."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.public_api_cidr)) && endswith(var.public_api_cidr, "/32")
    error_message = "Specify one public IPv4 address followed by /32."
  }
}

variable "cluster_admin_principal_arn" {
  description = "IAM role or user ARN for Kubernetes cluster-admin access."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:(role|user)/.+$", var.cluster_admin_principal_arn))
    error_message = "Specify the IAM role or user ARN."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.35"
}
