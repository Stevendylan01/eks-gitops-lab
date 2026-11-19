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
