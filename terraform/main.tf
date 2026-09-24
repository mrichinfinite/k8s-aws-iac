data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]

  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Lab       = "kubernetes-calico-vxlan"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-nodes"
  description = "Kubernetes lab node security group"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nodes-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.nodes.id
  description       = "SSH administration"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "api_server" {
  security_group_id = aws_security_group.nodes.id
  description       = "Kubernetes API server"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 6443
  ip_protocol       = "tcp"
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "etcd" {
  security_group_id = aws_security_group.nodes.id
  description       = "etcd client/server traffic"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 2379
  ip_protocol       = "tcp"
  to_port           = 2380
}

resource "aws_vpc_security_group_ingress_rule" "kubelet" {
  security_group_id = aws_security_group.nodes.id
  description       = "Kubelet API"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 10250
  ip_protocol       = "tcp"
  to_port           = 10250
}

resource "aws_vpc_security_group_ingress_rule" "vxlan" {
  security_group_id = aws_security_group.nodes.id
  description       = "Calico VXLAN"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 4789
  ip_protocol       = "udp"
  to_port           = 4789
}

resource "aws_vpc_security_group_ingress_rule" "nodeport_tcp" {
  security_group_id = aws_security_group.nodes.id
  description       = "Kubernetes NodePort TCP"
  cidr_ipv4         = var.nodeport_cidr
  from_port         = 30000
  ip_protocol       = "tcp"
  to_port           = 32767
}

resource "aws_vpc_security_group_ingress_rule" "nodeport_udp" {
  security_group_id = aws_security_group.nodes.id
  description       = "Kubernetes NodePort UDP"
  cidr_ipv4         = var.nodeport_cidr
  from_port         = 30000
  ip_protocol       = "udp"
  to_port           = 32767
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.nodes.id
  description       = "Lab node outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "control_plane" {
  ami                         = var.ubuntu_ami_id
  instance_type               = var.control_plane_instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.nodes.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-control-plane"
    Role = "control-plane"
  })
}

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = var.ubuntu_ami_id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.nodes.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-worker-${count.index + 1}"
    Role = "worker"
  })
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/aws.ini"

  content = templatefile("${path.module}/templates/inventory.tftpl", {
    control_plane_public_ip  = aws_instance.control_plane.public_ip
    control_plane_private_ip = aws_instance.control_plane.private_ip
    worker_public_ips        = aws_instance.worker[*].public_ip
    worker_private_ips       = aws_instance.worker[*].private_ip
    ssh_private_key_path     = var.ssh_private_key_path
  })
}
