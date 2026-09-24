# AWS Kubernetes + Calico VXLAN IaC Lab

This repository builds an ephemeral two-node Kubernetes lab in AWS:

- Ubuntu 26.04 EC2
- Kubernetes v1.31 packages / kubeadm
- 1 control-plane node
- 1+ worker nodes
- containerd
- Calico v3.32.2
- Calico BGP disabled
- Calico VXLAN enabled
- nginx workload
- curl test pod
- automated pod-to-pod connectivity validation

## Architecture

```text
AWS VPC
└── Public subnet
    ├── Control Plane EC2
    │   ├── kube-apiserver :6443
    │   ├── etcd :2379-2380
    │   └── kubelet :10250
    │
    └── Worker EC2
        └── kubelet :10250

Kubernetes
└── Calico
    ├── BGP: Disabled
    └── VXLAN: Enabled
        └── Pod network: 192.168.0.0/16

Workloads
├── nginx
└── curl
    └── curl http://nginx.default.svc.cluster.local
```

## Versions

| Component | Version |
|---|---|
| Ubuntu | 26.04 |
| Kubernetes | v1.31.14 |
| Calico | v3.32.2 |
| Container runtime | containerd from Ubuntu repository |

The Kubernetes APT repository is pinned to the v1.31 channel and the installed Kubernetes packages are held after installation. For strict reproducibility, set `kubernetes_package_version` to the exact package version available in your AWS/Ubuntu environment.

## Prerequisites

- AWS account
- AWS CLI configured
- Terraform >= 1.6
- Ansible >= 2.16
- SSH private key corresponding to the EC2 key pair
- An AWS region containing Ubuntu 26.04 AMIs
- An AWS key pair already created
- Your public IP/CIDR for SSH access

Terraform creates the AWS infrastructure. Ansible configures the operating system and Kubernetes. Kubernetes manifests configure Calico and workloads.

## Quick start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
terraform init
terraform plan
terraform apply
```

Then:

```bash
cd ../
ansible-playbook -i ansible/inventory/aws.ini ansible/playbooks/site.yml
```

Validate:

```bash
ansible-playbook -i ansible/inventory/aws.ini ansible/playbooks/validate.yml
```

Retrieve kubeconfig:

```bash
./scripts/get-kubeconfig.sh
```

Then:

```bash
export KUBECONFIG="$PWD/artifacts/admin.conf"
kubectl get nodes -o wide
kubectl get pods -A
```

Run the application test directly:

```bash
kubectl apply -f kubernetes/nginx.yaml
kubectl apply -f kubernetes/curl.yaml
kubectl wait --for=condition=Ready pod/nginx --timeout=180s
kubectl wait --for=condition=Ready pod/curl --timeout=180s
kubectl exec curl -- curl -fsS http://nginx.default.svc.cluster.local
```

## Destroy

```bash
cd terraform
terraform destroy
```

## Security model

SSH is restricted to `admin_cidr`.

Kubernetes node-to-node traffic is restricted to the VPC CIDR rather than the public Internet. The SG permits:

- TCP 6443 to the control plane
- TCP 2379-2380 to the control plane
- TCP 10250 between nodes
- UDP 4789 between nodes for Calico VXLAN
- optional NodePort TCP/UDP 30000-32767 from `nodeport_cidr`

Ports 10257 and 10259 are control-plane component ports and normally bind to localhost; they are therefore not exposed by the EC2 security group.

For a production design, use private subnets, NAT/VPC endpoints, SSM, IAM roles, and tighter network policy. This repository intentionally starts with a simple public-subnet lab topology.

## Design principle

The project deliberately keeps responsibilities separate:

```text
Terraform
  -> AWS resources

Ansible
  -> Linux + containerd + kubeadm + cluster bootstrap

Kubernetes YAML
  -> Calico + workloads

Validation
  -> assertions about the resulting system
```
