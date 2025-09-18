output "kubeconfig_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
