#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts

CONTROL_PLANE_IP="$(cd terraform && terraform output -raw control_plane_public_ip)"
KEY_PATH="$(cd terraform && terraform console <<< 'var.ssh_private_key_path' | tr -d '"')"

scp -o StrictHostKeyChecking=no \
  -i "$KEY_PATH" \
  "ubuntu@${CONTROL_PLANE_IP}:/etc/kubernetes/admin.conf" \
  artifacts/admin.conf

# Replace the control-plane private endpoint with its public address for local access.
sed -i -E "s#https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:6443#https://${CONTROL_PLANE_IP}:6443#" artifacts/admin.conf

chmod 600 artifacts/admin.conf
echo "Kubeconfig written to artifacts/admin.conf"
echo "export KUBECONFIG=\"$PWD/artifacts/admin.conf\""
