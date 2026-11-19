# eks-gitops-lab
Terraform and gitops for practice eks deployment

## Bootstrap ECR and GitHub Actions

Run this Terraform root locally with AWS credentials that can provision ECR and IAM. Set `aws_region` in `infra/bootstrap/local.tfvars`. If the AWS account already has an IAM OIDC provider for `token.actions.githubusercontent.com` with the `sts.amazonaws.com` audience, set `github_oidc_provider_arn` in that file to reuse it.

```sh
cd infra/bootstrap
terraform init
terraform plan -var-file=local.tfvars -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output -json github_actions_variables
```

Add the three output values as Actions repository variables in `Stevendylan01/go-node-info`. That repository's publishing workflow assumes the role from `main` and pushes its image to ECR. The trust policy uses GitHub's immutable OIDC subject format with the owner and repository IDs. [GitHub OIDC setup](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)

## Two-AZ EKS lab

The `infra/eks` Terraform root has its own state. It creates an EKS cluster with two private subnets, one on-demand managed worker per AZ, and one NAT gateway per AZ. Each worker uses its local NAT for egress. Kubernetes API access is private within the VPC and limited to the operator's public IPv4 address from outside it.

Apply `infra/bootstrap` first to create the dedicated EKS operator role. It trusts `AdminUser` by default and its AWS policy allows describing only this cluster. Copy `infra/eks/local.tfvars.example` to `infra/eks/local.tfvars`. Set your public IPv4 address with a `/32` suffix and use the output of `terraform -chdir=infra/bootstrap output -raw eks_operator_role_arn` as the principal ARN. The EKS root grants that role Kubernetes cluster-admin through an access entry.

```sh
cd infra/eks
terraform init
terraform plan -var-file=local.tfvars -out=eks.tfplan
terraform apply eks.tfplan
```

Configure an AWS CLI profile named `eks-lab-operator` with the operator role ARN as `role_arn` and your authenticated `AdminUser` profile as `source_profile`. Use it to configure and verify access.

```sh
aws eks update-kubeconfig --profile eks-lab-operator --region us-east-1 --name eks-gitops-lab
kubectl get nodes -L topology.kubernetes.io/zone
kubectl get pods -n kube-system
```

The worker and egress capacity in each AZ give the app somewhere to run during an AZ failure. The application still needs ready replicas spread across both AZs. Install and validate that separately.

When done, review and apply a destroy plan from `infra/eks`. Remove any Kubernetes services or ingress that provision AWS load balancers before destroying the cluster. The ECR repository and publishing role are in `infra/bootstrap`.

```sh
terraform plan -destroy -var-file=local.tfvars -out=eks-destroy.tfplan
terraform apply eks-destroy.tfplan
```
