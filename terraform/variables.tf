variable "aws_region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "k8s-calico-vxlan-lab"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the lab VPC."
  type        = string
  default     = "10.50.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR block for the public subnet."
  type        = string
  default     = "10.50.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone" {
  description = "Optional AZ. Leave empty to let AWS select the first AZ."
  type        = string
  default     = ""
}

variable "key_name" {
  description = "Existing AWS EC2 key-pair name."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Local path to the private SSH key corresponding to key_name."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the nodes, e.g. 203.0.113.10/32."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr))
    error_message = "admin_cidr must be a valid IPv4 CIDR block."
  }
}

variable "nodeport_cidr" {
  description = "CIDR allowed to access Kubernetes NodePorts. Use your own IP/32 for a lab or VPC CIDR for internal-only access."
  type        = string
  default     = "10.50.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.nodeport_cidr))
    error_message = "nodeport_cidr must be a valid IPv4 CIDR block."
  }
}

variable "control_plane_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}

variable "worker_count" {
  type    = number
  default = 1

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "worker_count must be between 1 and 10."
  }
}

variable "ubuntu_ami_id" {
  description = "Ubuntu 26.04 AMD64 AMI ID. Set explicitly for deterministic lab builds."
  type        = string
}

variable "root_volume_size_gb" {
  type    = number
  default = 30
}
