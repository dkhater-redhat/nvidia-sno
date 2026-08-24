#!/bin/bash
set -e

echo "========================================"
echo "SNO Configuration Script"
echo "========================================"
echo ""
echo "This script will configure all necessary files for SNO deployment."
echo "Please provide the following information:"
echo ""

# Gather configuration from user (with defaults)
# Use defaults if user just hits Enter
read -p "IP address [10.28.128.22]: " IP_ADDRESS
IP_ADDRESS=${IP_ADDRESS:-10.28.128.22}

read -p "Subnet mask in CIDR [28]: " SUBNET_MASK
SUBNET_MASK=${SUBNET_MASK:-28}

read -p "Gateway [10.28.128.17]: " GATEWAY
GATEWAY=${GATEWAY:-10.28.128.17}

read -p "Primary DNS [103.247.36.36]: " DNS_PRIMARY
DNS_PRIMARY=${DNS_PRIMARY:-103.247.36.36}

read -p "Secondary DNS: " DNS_SECONDARY

read -p "Network interface name [enP5p65s0f0np0]: " INTERFACE
INTERFACE=${INTERFACE:-enP5p65s0f0np0}

read -p "Disk ID [nvme-eui.385348304c3072860025384700000001]: " DISK_ID
DISK_ID=${DISK_ID:-nvme-eui.385348304c3072860025384700000001}

read -p "Hostname [vera-rubin]: " HOSTNAME
HOSTNAME=${HOSTNAME:-vera-rubin}

read -p "Domain [nvidia.local]: " DOMAIN
DOMAIN=${DOMAIN:-nvidia.local}

read -p "Network CIDR [10.28.128.16/28]: " NETWORK_CIDR
NETWORK_CIDR=${NETWORK_CIDR:-10.28.128.16/28}

FULL_HOSTNAME="${HOSTNAME}.${DOMAIN}"

echo ""
echo "========================================"
echo "Configuration Summary:"
echo "========================================"
echo "IP Address: ${IP_ADDRESS}/${SUBNET_MASK}"
echo "Gateway: ${GATEWAY}"
echo "DNS: ${DNS_PRIMARY}, ${DNS_SECONDARY}"
echo "Interface: ${INTERFACE}"
echo "Disk: /dev/disk/by-id/${DISK_ID}"
echo "Hostname: ${FULL_HOSTNAME}"
echo "Network CIDR: ${NETWORK_CIDR}"
echo "========================================"
echo ""
read -p "Continue with these settings? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Updating configuration files..."

# Export variables for envsubst
export IP_ADDRESS SUBNET_MASK GATEWAY DNS_PRIMARY DNS_SECONDARY
export INTERFACE DISK_ID HOSTNAME DOMAIN NETWORK_CIDR FULL_HOSTNAME

# Generate dnsmasq.bu from template using envsubst
echo "  - Generating dnsmasq.bu..."
envsubst < dnsmasq.bu.template > dnsmasq.bu

# Generate 99-cluster-dns-02-config.yaml from template using envsubst
echo "  - Generating local_openshift/99-cluster-dns-02-config.yaml..."
envsubst < local_openshift/99-cluster-dns-02-config.yaml.template > local_openshift/99-cluster-dns-02-config.yaml

# Generate 99-master-host-network-customizations.yaml from dnsmasq.bu using butane
echo "  - Generating local_openshift/99-master-host-network-customizations.yaml..."
# Create a temporary Butane file for MachineConfig (variant: openshift, remove ignition merge)
sed -e 's/variant: fcos/variant: openshift/' \
    -e 's/version: 1.5.0/version: 4.14.0/' \
    -e '/ignition:/,/local: bootstrap-in-place-for-live-iso.ign/d' \
    dnsmasq.bu > /tmp/host-network-customizations.bu
# Add MachineConfig metadata
cat > /tmp/99-master-host-network-customizations.bu << EOF
variant: openshift
version: 4.14.0
metadata:
  name: 99-master-host-network-customizations
  labels:
    machineconfiguration.openshift.io/role: master
EOF
# Append the storage, passwd, and systemd sections from dnsmasq.bu
sed -n '/^storage:/,$ p' /tmp/host-network-customizations.bu >> /tmp/99-master-host-network-customizations.bu
butane --pretty --strict /tmp/99-master-host-network-customizations.bu -o local_openshift/99-master-host-network-customizations.yaml
rm -f /tmp/host-network-customizations.bu /tmp/99-master-host-network-customizations.bu

echo ""
echo "========================================"
echo "Configuration complete!"
echo "========================================"
echo ""
echo "Generated files:"
echo "  - dnsmasq.bu (from template)"
echo "  - local_openshift/99-cluster-dns-02-config.yaml (from template)"
echo "  - local_openshift/99-master-host-network-customizations.yaml (from dnsmasq.bu via Butane)"
echo ""
echo "Next steps:"
echo "  1. Ensure ssh.pub and pull-secret.json files exist in this directory"
echo "  2. Run: VERSION=5.0 ./create_sno_iso.sh"
echo ""
