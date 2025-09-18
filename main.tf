provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# Adding this to fetch available Availability Zones in the selected region dynamically
data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source             = "./modules/vpc"
  project_name       = var.project_name
  aws_region         = var.aws_region
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "eks" {
  source              = "./modules/eks"
  project_name        = var.project_name
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
}

# -------------------------------------------PHASE 2-----------------------------------------------
# Going with EKS Pod Identity Agent

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# ---  IAM Role for AWS Load Balancer Controller ---
resource "aws_iam_role" "alb_controller" {
  name = "${var.project_name}-alb-controller-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "pods.eks.amazonaws.com" },
      Action    = ["sts:AssumeRole",
      "sts:TagSession"]
    }]
  })
}

data "http" "alb_controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for the AWS Load Balancer Controller"
  policy      = data.http.alb_controller_iam_policy.response_body
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = aws_iam_role.alb_controller.name
}

# --- EKS Pod Identity Association ---
resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn
  depends_on      = [module.eks]
}

# --- Helm Chart Installations ---

# This is the resource block that was likely missing or misnamed.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

set = [{
    name  = "clusterName"
    value = module.eks.cluster_name
  }, {
    name  = "serviceAccount.create"
    value = "true"
  }, {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }, {
    # CRITICAL: Explicit region configuration to avoid metadata access issues
    name  = "region"
    value = var.aws_region
  }, {
    # CRITICAL: Explicit VPC ID configuration - this is the key fix for your error
    name  = "vpcId"
    value = module.vpc.vpc_id
  }]
  
  depends_on = [aws_eks_pod_identity_association.alb_controller]
}

# This 'depends_on' block refers to the resource block above.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "6.11.1"

   set =[{
    name  = "server.extraArgs"
    value = "{--insecure}"
  }]
  depends_on = [helm_release.aws_load_balancer_controller]
}