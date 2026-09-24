# AWS Kubernetes + Calico VXLAN IaC Lab

This repository builds an ephemeral Kubernetes networking lab in AWS using Terraform, Ansible, kubeadm, and Calico.

The default topology consists of:

- Ubuntu 26.04 EC2 instances
- Kubernetes v1.31.14
- 1 control-plane node
- 1 worker node by default
- containerd
- Calico v3.32.2
- Calico BGP disabled
- Calico VXLAN enabled
- nginx test workload
- curl test pod
- automated cross-node connectivity validation

The project is designed as an Infrastructure as Code reference lab. Git is the source of truth for the infrastructure, cluster configuration, workload manifests, and validation logic.

## Architecture

```text
AWS VPC
└── Public subnet
    ├── Control Plane EC2
    │   ├── kube-apiserver :6443
    │   ├── etcd :2379-2380
    │   ├── kubelet :10250
    │   └── nginx pod
    │
    └── Worker EC2
        ├── kubelet :10250
        └── curl pod

Kubernetes
└── Calico
    ├── BGP: Disabled
    ├── VXLAN: Enabled
    └── Pod network: 192.168.0.0/16

Cross-node validation path:

curl pod (worker)
        │
        │ Kubernetes Service
        ▼
nginx Service
        │
        ▼
nginx pod (control plane)
```

The workload scheduling rules intentionally place nginx on the control-plane node and curl on a worker. This makes the connectivity test cross-node rather than allowing both test workloads to run on the same host.

## Design

Responsibilities are deliberately separated:

```text
Terraform
  -> AWS infrastructure
  -> generated Ansible inventory

Ansible
  -> Linux configuration
  -> containerd
  -> Kubernetes packages
  -> kubeadm cluster bootstrap
  -> Calico installation
  -> workload deployment

Kubernetes YAML
  -> workload definitions and scheduling

Validation
  -> cluster health
  -> Calico configuration
  -> cross-node test topology
  -> application connectivity
```

The top-level `kubernetes/` directory is the source of truth for workload manifests. Ansible deploys those manifests rather than maintaining duplicate copies.

## Versions

| Component | Version strategy |
|---|---|
| Ubuntu | 26.04 |
| Kubernetes | v1.31.14 / package 1.31.14-1.1 |
| Calico | v3.32.2 |
| containerd | Ubuntu repository |
| nginx | `latest` |
| curl | `latest` |

Kubernetes and Calico are intentionally pinned because they form part of the cluster compatibility contract.

The nginx and curl images use `latest` because they are disposable connectivity-test workloads rather than infrastructure dependencies.

## Prerequisites

Before deploying the lab, you need:

- AWS account
- AWS CLI installed and authenticated
- Terraform >= 1.6
- Ansible Core 2.21.4
- required Ansible collections from `ansible/requirements.yml`
- an existing AWS EC2 key pair
- the corresponding local SSH private key
- an Ubuntu 26.04 AMD64 AMI ID for the selected AWS region
- your public IP address/CIDR for administrative access

AWS credentials and SSH private keys must not be committed to the repository.

Install the required Ansible collections with:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

## Configure Terraform

Create your local variable file:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars
```

At minimum, review the AWS region, Ubuntu AMI, EC2 key pair, SSH private-key path, and administrative CIDR.

`terraform.tfvars` is intentionally excluded from Git.

## Deploy

Initialize and validate Terraform:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan
```

Create the AWS infrastructure:

```bash
terraform -chdir=terraform apply
```

Terraform also generates:

```text
ansible/inventory/aws.ini
```

using the EC2 addresses and configured SSH key.

Deploy Kubernetes and Calico:

```bash
ansible-playbook \
  -i ansible/inventory/aws.ini \
  ansible/playbooks/site.yml
```

The playbook is designed to be safely rerunnable. Existing cluster bootstrap operations are skipped, and declarative resources are reconciled against their desired state.

The disposable curl test pod is intentionally recreated during deployment and therefore reports a legitimate Ansible `changed` result on subsequent runs.

## Validate

Run the automated validation suite:

```bash
ansible-playbook \
  -i ansible/inventory/aws.ini \
  ansible/playbooks/validate.yml
```

Validation checks that:

- the expected Kubernetes nodes exist and are Ready
- the expected Calico node agents are Ready
- the expected Calico version is installed
- Calico BGP is disabled
- Calico VXLAN encapsulation is configured
- exactly one nginx test pod exists
- curl and nginx are running on different Kubernetes nodes
- the nginx Service endpoint references the nginx pod
- curl can successfully reach nginx through the Kubernetes Service

The final connectivity test therefore provides a functional cross-node networking test while separately asserting that Calico is configured for VXLAN encapsulation.

It does not perform packet capture or claim to directly observe UDP/4789 encapsulation on the wire.

## Access the cluster

Retrieve the administrative kubeconfig:

```bash
./scripts/get-kubeconfig.sh
```

Then:

```bash
export KUBECONFIG="$PWD/artifacts/admin.conf"

kubectl get nodes -o wide
kubectl get pods -A -o wide
```

A direct application test can also be run with:

```bash
kubectl exec curl -- \
  curl -fsS http://nginx.default.svc.cluster.local
```

## CI

GitHub Actions performs static validation on pushes to `main` and on pull requests.

CI currently performs:

- Terraform formatting validation
- Terraform initialization without a remote backend
- Terraform configuration validation
- Ansible dependency installation
- Ansible playbook syntax validation

CI intentionally does not run `terraform apply` or create AWS resources. Live infrastructure deployment remains an explicit human-controlled operation.

## Security model

Administrative SSH access is restricted to `admin_cidr`.

Kubernetes API access from the administrator workstation is also restricted to `admin_cidr`.

Cluster traffic is restricted to the VPC CIDR. The shared node security group permits the traffic required by this lab, including:

- TCP 6443 for the Kubernetes API
- TCP 2379-2380 for etcd
- TCP 10250 for kubelet
- TCP 5473 for Calico Typha
- UDP 4789 for Calico VXLAN
- TCP/UDP 30000-32767 from `nodeport_cidr` for NodePort services

Outbound traffic is permitted so the nodes can retrieve packages, container images, and required deployment artifacts.

Ports 10257 and 10259 are not exposed by the EC2 security group.

## Lab scope and limitations

This repository is a lab/reference implementation, not a production Kubernetes architecture.

The design intentionally uses:

- a single control-plane node
- a public subnet
- public EC2 addresses
- a shared node security group
- local Terraform state
- direct SSH administration
- kubeadm rather than a managed Kubernetes service

A production AWS Kubernetes design would require additional architectural decisions around high availability, private networking, identity and access management, secrets, state storage, observability, upgrades, backup/recovery, and other operational requirements.

Those concerns are deliberately outside the scope of this lab.

## Destroy

When finished, destroy the AWS infrastructure to avoid unnecessary charges:

```bash
terraform -chdir=terraform destroy
```

Review the Terraform destroy plan before confirming.

## Repository layout

```text
.
├── terraform/              # AWS infrastructure
├── ansible/                # Host and Kubernetes automation
├── kubernetes/             # Workload source-of-truth manifests
├── scripts/                # Deployment/helper scripts
└── .github/workflows/      # Static CI validation
```

## License

This project is licensed under the MIT License. See `LICENSE` for details.
