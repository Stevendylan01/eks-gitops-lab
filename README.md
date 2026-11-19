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

### Tear down

Run from the repository root. Remove the Argo CD Application first so it cannot recreate the Ingress. Wait for the Ingress deletion to finish and confirm the lab ALB has disappeared before running Terraform.

```sh
kubectl --context eks-gitops-lab -n argocd delete application go-node-info --ignore-not-found
kubectl --context eks-gitops-lab -n go-node-info delete ingress go-node-info --ignore-not-found --timeout=5m
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[].DNSName'
terraform -chdir=infra/eks destroy -var-file=local.tfvars
```

The EKS Terraform root includes the cluster, workers, NAT gateways, public IPs, and VPC. The separate bootstrap IAM resources, load balancer controller role and policy, ECR images, and ACM certificate stay available. ECR storage can still incur charges.

### Rebuild

Use the infrastructure AWS profile for Terraform and IAM commands. If the operator session has expired, refresh it with `aws login --profile eks-lab-admin --remote`.

```sh
terraform -chdir=infra/eks init
terraform -chdir=infra/eks apply -var-file=local.tfvars
aws eks update-kubeconfig --profile eks-lab-operator --region us-east-1 --name eks-gitops-lab --alias eks-gitops-lab
```

A new cluster has a new OIDC issuer. Register it and point the existing load balancer controller role at it.

```sh
issuer=$(aws eks describe-cluster --region us-east-1 --name eks-gitops-lab --query cluster.identity.oidc.issuer --output text)
provider=$(aws iam create-open-id-connect-provider --url "$issuer" --client-id-list sts.amazonaws.com --query OpenIDConnectProviderArn --output text)
aws iam update-assume-role-policy --role-name eks-gitops-lab-lbc --policy-document "$(
  jq -n --arg provider "$provider" --arg issuer "${issuer#https://}" '
    {Version:"2012-10-17",Statement:[{
      Effect:"Allow",Principal:{Federated:$provider},Action:"sts:AssumeRoleWithWebIdentity",
      Condition:{StringEquals:{($issuer+":aud"):"sts.amazonaws.com",
        ($issuer+":sub"):"system:serviceaccount:kube-system:aws-load-balancer-controller"}}
    }]}'
)"
```

Install the controller and Argo CD, then apply the existing Application.

```sh
vpc=$(aws eks describe-cluster --region us-east-1 --name eks-gitops-lab --query cluster.resourcesVpcConfig.vpcId --output text)
role=$(aws iam get-role --role-name eks-gitops-lab-lbc --query Role.Arn --output text)
helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller \
  --repo https://aws.github.io/eks-charts --version 3.6.3 --namespace kube-system \
  --set clusterName=eks-gitops-lab --set region=us-east-1 --set "vpcId=$vpc" \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$role" \
  --set featureGates.ALBGatewayAPI=false --set featureGates.NLBGatewayAPI=false \
  --set enableServiceMutatorWebhook=false --wait

kubectl create namespace argocd
kubectl -n argocd apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.2/manifests/install.yaml
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=2m
kubectl apply -f gitops/go-node-info.application.yaml
kubectl -n go-node-info get ingress go-node-info
```

Once the Ingress shows an address, update the Cloudflare CNAME for `go.stevenslab.net` to that address. The Ingress reuses the existing ACM certificate.
