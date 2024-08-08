provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "aws_security_group" {
  name_prefix = "SecurityGroup-EKS"
  description = "This Security group contains ssh access from all CiscoVPN in Americas"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/32"]
    description = "Open To World on TcP" # Replace with specific IP ranges if needed
  }
}

#####EKS Cluster

resource "aws_eks_cluster" "my_cluster" {
  name     = "abhi-eks-cluster"
  role_arn = aws_iam_role.eks_cluster.arn  
  vpc_config {
    subnet_ids          = flatten([aws_subnet.my_public_subnets.*.id, aws_subnet.my_private_subnets.*.id])
    security_group_ids  = [aws_security_group.aws_security_group.id]
  }

  depends_on = [
    aws_iam_policy_attachment.eks_cluster_policy_attachment_1
  ]

}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "eks_cluster_policy_attachment_1" {
  name       = "eks-cluster-policy-attachment-1"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  roles      = [aws_iam_role.eks_cluster.name]
}

resource "aws_iam_policy_attachment" "eks_cluster_policy_attachment_2" {
  name       = "eks-cluster-policy-attachment-2"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  roles      = [aws_iam_role.eks_cluster.name]
}

resource "aws_iam_policy_attachment" "eks_cluster_policy_attachment_3" {
  name       = "eks-cluster-policy-attachment-3"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  roles      = [aws_iam_role.eks_cluster.name]
}

output "eks_cluster_name" {
  value = aws_eks_cluster.my_cluster.name
}

output "eks_role_name" {
  value = aws_iam_role.eks_cluster.name
}

data "aws_ssm_parameter" "eks_ami_release_version" {
  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.my_cluster.version}/amazon-linux-2/recommended/release_version"
}

##Node Group

resource "aws_eks_node_group" "my_node_group" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "my-node-group"
  version         = aws_eks_cluster.my_cluster.version
  release_version = nonsensitive(data.aws_ssm_parameter.eks_ami_release_version.value)
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids =    aws_subnet.my_private_subnets.*.id  
  

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_worker_policy,
    aws_iam_role_policy_attachment.eks_node_group_ecr_policy,
    aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
  ]

}

resource "aws_iam_role" "eks_node_group" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_group_worker_policy" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_group_ecr_policy" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role      = aws_iam_role.eks_node_group.name
}


output "eks_node_group_name" {
  value = aws_eks_node_group.my_node_group.node_group_name
}


variable "networking" {
  type = object({
    cidr_block      = string
    region          = string
    vpc_name        = string
    azs             = list(string)
    public_subnets  = list(string)
    private_subnets = list(string)
    nat_gateways    = bool
  })
  default = {
    cidr_block      = "10.0.0.0/16"
    region          = "us-east-1"
    vpc_name        = "custom-vpc"
    azs             = ["us-east-1a", "us-east-1b"]
    public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
    private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
    nat_gateways    = true
  }
}

resource "aws_vpc" "my_vpc" {
  cidr_block = var.networking.cidr_block
  tags = {
    Name = "eks-vpc",
    Owner = "abhibaj@cisco.com"
  }
}


resource "aws_subnet" "my_public_subnets" {
  count = var.networking.public_subnets == null || var.networking.public_subnets == "" ? 0 : length(var.networking.public_subnets)
  cidr_block = var.networking.public_subnets[count.index]
  vpc_id     = aws_vpc.my_vpc.id
  availability_zone = var.networking.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public_subnet-${count.index}"
  }
}

resource "aws_subnet" "my_private_subnets" {
  count                   = var.networking.private_subnets == null || var.networking.private_subnets == "" ? 0 : length(var.networking.private_subnets)
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = var.networking.private_subnets[count.index]
  availability_zone       = var.networking.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "private_subnet-${count.index}"
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "Abhi-igw"
  }
}


resource "aws_eip" "elastic_ip" {
  count      = var.networking.private_subnets == null || var.networking.nat_gateways == false ? 0 : length(var.networking.private_subnets)
  vpc        = true
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "eip-${count.index}"
  }
}

resource "aws_nat_gateway" "nats" {
  count             = var.networking.private_subnets == null || var.networking.nat_gateways == false ? 0 : length(var.networking.private_subnets)
  subnet_id         = aws_subnet.my_public_subnets[count.index].id
  connectivity_type = "public"
  allocation_id     = aws_eip.elastic_ip[count.index].id
  depends_on        = [aws_internet_gateway.igw]
}

# PUBLIC ROUTE TABLES
resource "aws_route_table" "public_table" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route" "public_routes" {
  route_table_id         = aws_route_table.public_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_table_association" {
  count          = length(var.networking.public_subnets)
  subnet_id      = aws_subnet.my_public_subnets[count.index].id
  route_table_id = aws_route_table.public_table.id
}

# PRIVATE ROUTE TABLES
resource "aws_route_table" "private_tables" {
  count  = length(var.networking.azs)
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_route" "private_routes" {
  count                  = length(var.networking.private_subnets)
  route_table_id         = aws_route_table.private_tables[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nats[count.index].id
}

resource "aws_route_table_association" "private_table_association" {
  count          = length(var.networking.private_subnets)
  subnet_id      = aws_subnet.my_private_subnets[count.index].id
  route_table_id = aws_route_table.private_tables[count.index].id
}




