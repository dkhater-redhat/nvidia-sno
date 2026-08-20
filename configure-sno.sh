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

read -p "Secondary DNS [8.8.8.8]: " DNS_SECONDARY
DNS_SECONDARY=${DNS_SECONDARY:-8.8.8.8}

read -p "Network interface name [enP5p65s0f0np0]: " INTERFACE
INTERFACE=${INTERFACE:-enP5p65s0f0np0}

read -p "Disk ID [nvme-eui.385348304c3072860025384700000001]: " DISK_ID
DISK_ID=${DISK_ID:-nvme-eui.385348304c3072860025384700000001}

read -p "Hostname [vera-rubin]: " HOSTNAME
HOSTNAME=${HOSTNAME:-vera-rubin}

read -p "Domain [nvidia.local]: " DOMAIN
DOMAIN=${DOMAIN:-nvidia.local}

# Calculate network CIDR for machineNetwork
# Properly calculate network address for any subnet mask
IFS='.' read -ra IP_PARTS <<< "$IP_ADDRESS"
LAST_OCTET=${IP_PARTS[3]}

# Calculate the network address based on subnet mask
if [ "$SUBNET_MASK" -ge 24 ]; then
    # For /24 and smaller (more specific), calculate the network portion of the last octet
    HOST_BITS=$((32 - SUBNET_MASK))
    BLOCK_SIZE=$((1 << HOST_BITS))
    NETWORK_LAST_OCTET=$((LAST_OCTET / BLOCK_SIZE * BLOCK_SIZE))
    NETWORK_BASE="${IP_PARTS[0]}.${IP_PARTS[1]}.${IP_PARTS[2]}.${NETWORK_LAST_OCTET}"
elif [ "$SUBNET_MASK" -ge 16 ]; then
    # For /16-/23, third octet changes
    HOST_BITS=$((32 - SUBNET_MASK))
    BLOCK_SIZE=$((1 << (HOST_BITS - 8)))
    NETWORK_THIRD_OCTET=$((IP_PARTS[2] / BLOCK_SIZE * BLOCK_SIZE))
    NETWORK_BASE="${IP_PARTS[0]}.${IP_PARTS[1]}.${NETWORK_THIRD_OCTET}.0"
else
    # For /8-/15, second octet changes
    HOST_BITS=$((32 - SUBNET_MASK))
    BLOCK_SIZE=$((1 << (HOST_BITS - 16)))
    NETWORK_SECOND_OCTET=$((IP_PARTS[1] / BLOCK_SIZE * BLOCK_SIZE))
    NETWORK_BASE="${IP_PARTS[0]}.${NETWORK_SECOND_OCTET}.0.0"
fi

NETWORK_CIDR="${NETWORK_BASE}/${SUBNET_MASK}"

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

# Helper function to escape strings for sed
escape_sed() {
    echo "$1" | sed -e 's/[\/&]/\\&/g' -e 's/\$/\\$/g'
}

# Update dnsmasq.bu using sed
echo "  - Updating dnsmasq.bu..."
sed -i.bak \
    -e "s/inline: .*/inline: ${FULL_HOSTNAME}/" \
    -e "s/id=.*/id=${INTERFACE}/" \
    -e "s/interface-name=.*/interface-name=${INTERFACE}/" \
    -e "s/addresses=.*/addresses=${IP_ADDRESS}\/${SUBNET_MASK}/" \
    -e "s/gateway=.*/gateway=${GATEWAY}/" \
    -e "s/dns=.*/dns=${DNS_PRIMARY};${DNS_SECONDARY}/" \
    -e "s|local=/.*|local=/${FULL_HOSTNAME}/|" \
    -e "s|address=/api\..*|address=/api.${FULL_HOSTNAME}/${IP_ADDRESS}|" \
    -e "s|address=/api-int\..*|address=/api-int.${FULL_HOSTNAME}/${IP_ADDRESS}|" \
    -e "s|address=/apps\..*|address=/apps.${FULL_HOSTNAME}/${IP_ADDRESS}|" \
    -e "s|listen-address=${IP_ADDRESS}.*|listen-address=${IP_ADDRESS}|" \
    -e "/server=/d" \
    dnsmasq.bu

# Add server lines back
sed -i.bak2 \
    "/listen-address=127.0.0.1/a\\
          server=${DNS_PRIMARY}\\
          server=${DNS_SECONDARY}" \
    dnsmasq.bu

rm -f dnsmasq.bu.bak dnsmasq.bu.bak2

# Update install-config.yaml.template using sed
echo "  - Updating install-config.yaml.template..."
sed -i.bak \
    -e "s/baseDomain: .*/baseDomain: ${DOMAIN}/" \
    -e "s/  name: .*/  name: ${HOSTNAME}/" \
    -e "s|- cidr: .*|- cidr:  ${NETWORK_CIDR}|" \
    -e "s|installationDisk: .*|installationDisk: /dev/disk/by-id/${DISK_ID}|" \
    install-config.yaml.template
rm -f install-config.yaml.template.bak

# Update 99-cluster-dns-02-config.yaml using sed
echo "  - Updating local_openshift/99-cluster-dns-02-config.yaml..."
sed -i.bak \
    -e "s/address: .*/address: ${IP_ADDRESS}/" \
    local_openshift/99-cluster-dns-02-config.yaml
rm -f local_openshift/99-cluster-dns-02-config.yaml.bak

# Create temporary network and dnsmasq configs for base64 encoding
echo "  - Creating base64-encoded configs..."
mkdir -p /tmp/sno-config-$$

cat > /tmp/sno-config-$$/network.txt << EOF
[connection]
id=${INTERFACE}
type=ethernet
interface-name=${INTERFACE}
autoconnect=true

[ipv4]
method=manual
addresses=${IP_ADDRESS}/${SUBNET_MASK}
gateway=${GATEWAY}
dns=${DNS_PRIMARY};${DNS_SECONDARY}
EOF

cat > /tmp/sno-config-$$/dnsmasq.txt << EOF
local=/${FULL_HOSTNAME}/
address=/api.${FULL_HOSTNAME}/${IP_ADDRESS}
address=/api-int.${FULL_HOSTNAME}/${IP_ADDRESS}
address=/apps.${FULL_HOSTNAME}/${IP_ADDRESS}
listen-address=127.0.0.1
listen-address=${IP_ADDRESS}
cache-size=1000
server=${DNS_PRIMARY}
server=${DNS_SECONDARY}
EOF

# Generate base64 encoded configs
NETWORK_BASE64=$(cat /tmp/sno-config-$$/network.txt | gzip -c | base64)
DNSMASQ_BASE64=$(cat /tmp/sno-config-$$/dnsmasq.txt | gzip -c | base64)

# Update 99-master-host-network-customizations.yaml using sed
echo "  - Updating local_openshift/99-master-host-network-customizations.yaml..."

# Escape special characters for sed
FULL_HOSTNAME_ESC=$(escape_sed "$FULL_HOSTNAME")
NETWORK_BASE64_ESC=$(escape_sed "$NETWORK_BASE64")
DNSMASQ_BASE64_ESC=$(escape_sed "$DNSMASQ_BASE64")
INTERFACE_ESC=$(escape_sed "$INTERFACE")

sed -i.bak \
    -e "s|source: data:,.*nvidia.local|source: data:,${FULL_HOSTNAME_ESC}|" \
    -e "s|path: /etc/NetworkManager/system-connections/.*.nmconnection|path: /etc/NetworkManager/system-connections/${INTERFACE_ESC}.nmconnection|" \
    -e "s|source: data:;base64,.*|source: data:;base64,${NETWORK_BASE64_ESC}|" \
    local_openshift/99-master-host-network-customizations.yaml

# Update the dnsmasq base64 (line after "path: /etc/NetworkManager/dnsmasq.d/ocp-sno.conf")
sed -i.bak2 \
    "/path: \/etc\/NetworkManager\/dnsmasq.d\/ocp-sno.conf/,/source: data:;base64,/ s|source: data:;base64,.*|source: data:;base64,${DNSMASQ_BASE64_ESC}|" \
    local_openshift/99-master-host-network-customizations.yaml

rm -f local_openshift/99-master-host-network-customizations.yaml.bak*

# Clean up temp files
rm -rf /tmp/sno-config-$$

echo ""
echo "========================================"
echo "Configuration complete!"
echo "========================================"
echo ""
echo "Updated files:"
echo "  - dnsmasq.bu"
echo "  - install-config.yaml.template"
echo "  - local_openshift/99-cluster-dns-02-config.yaml"
echo "  - local_openshift/99-master-host-network-customizations.yaml"
echo ""
echo "Next steps:"
echo "  1. Ensure ssh.pub and pull-secret.json files exist in this directory"
echo "  2. Run: VERSION=5.0 ./create_sno_iso.sh"
echo ""
