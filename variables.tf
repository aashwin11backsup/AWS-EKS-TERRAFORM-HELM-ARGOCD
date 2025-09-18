variable "aws_region" {
  description = "The AWS region to deploy all resources in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "A name for the project, used to prefix resources."
  type        = string
  default     = "staging-eks-demo"
}