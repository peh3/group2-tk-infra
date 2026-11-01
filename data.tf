data "aws_availability_zones" "aws_az" {
  state = "available"
}

# data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}