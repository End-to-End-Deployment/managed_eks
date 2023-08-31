This repository will help you create an EKS cluster 
resource "aws_eks_cluster" "my_cluster" {
  name     = "abhi-eks-cluster"
}

You can edit the name. We will also create an IGW, NatGw and all the required subnets in the VPC
