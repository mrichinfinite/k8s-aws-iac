#!/usr/bin/env bash
set -euo pipefail

terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan
terraform -chdir=terraform apply
ansible-playbook -i ansible/inventory/aws.ini ansible/playbooks/site.yml
ansible-playbook -i ansible/inventory/aws.ini ansible/playbooks/validate.yml
