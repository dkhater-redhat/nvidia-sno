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

# Update dnsmasq.bu
echo "  - Updating dnsmasq.bu..."
cat > dnsmasq.bu << EOF
variant: fcos
version: 1.5.0

ignition:
  config:
    merge:
      - local: bootstrap-in-place-for-live-iso.ign

passwd:
  users:
    - name: core
      password_hash: "\$6\$jamyHU6tcWovxP.e\$rasKzY7tDn.LlazCF6Z4osY86aaXGEFOnkDSClPCw1B/DzPn2knv/kHCwncynti2r3k8MSLwcEsyEwqkDwZd8/"
      ssh_authorized_keys:
        - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7zgvPt+AVZF06sA0jRY6MByNyytlGsMn6z+KMjjX7/ dkhater@redhat.com-sno
        - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDgBv89yZuWD1AfOi+3CGI7FWawpwYQVrxLCjfxPnP7KjEGGAHGsorce5XGNu1W57ND8HrdLyQf4SLfHAwVyRvRfIf8NzakUuxR4khHCpxE+F8ByTyg23Y17DkfBM/RCXcdMU1vvDkfCdsVMOY8KKhLL412560KfxQhQBKsCmssMZQ4Ii5b18cJfbwk+JnNC0fRiV/h2qrOsRQ7XvJynHHxMfqfih3BLnVo83FSf3G7T9LwpS7BQK4BsO14ahztMXxkU7j+ZdRd3+gUK3L9E0Y/fdtrMXgnG6OphkFEGTY7hlpV9Ppr7t5mDDl6LPMDWpWaZ0xz61IqKbrjXVPv63xF ravanelli@renatas-air.br.ibm.com

storage:
  files:
    - path: /etc/hostname
      mode: 0644
      overwrite: true
      contents:
        inline: ${FULL_HOSTNAME}
    - path: /etc/NetworkManager/system-connections/${INTERFACE}.nmconnection
      mode: 0600
      overwrite: true
      contents:
        inline: |
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

    - path: /etc/NetworkManager/dnsmasq.d/ocp-sno.conf
      mode: 0644
      overwrite: true
      contents:
        inline: |
          local=/${FULL_HOSTNAME}/
          address=/api.${FULL_HOSTNAME}/${IP_ADDRESS}
          address=/api-int.${FULL_HOSTNAME}/${IP_ADDRESS}
          address=/apps.${FULL_HOSTNAME}/${IP_ADDRESS}
          listen-address=127.0.0.1
          listen-address=${IP_ADDRESS}
          cache-size=1000
          server=${DNS_PRIMARY}
          server=${DNS_SECONDARY}

    - path: /etc/NetworkManager/conf.d/dnsmasq.conf
      mode: 0644
      overwrite: true
      contents:
        inline: |
          [main]
          dns=dnsmasq

    - path: /etc/ssh/sshd_config.d/01-password-auth.conf
      mode: 0644
      overwrite: true
      contents:
        inline: |
          PasswordAuthentication yes

systemd:
  units:
    - name: dnsmasq.service
      enabled: false
      mask: true
EOF

# Update install-config.yaml.template
echo "  - Updating install-config.yaml.template..."
cat > install-config.yaml.template << EOF
apiVersion: v1
baseDomain: ${DOMAIN}
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 1
metadata:
  name: ${HOSTNAME}
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr:  ${NETWORK_CIDR}
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
bootstrapInPlace:
  installationDisk: /dev/disk/by-id/${DISK_ID}
osImageStream: "rhel-10"
featureSet: TechPreviewNoUpgrade
pullSecret: |
  \${PULL_SECRET}
sshKey: |
  \${SSH_KEY}
EOF

# Update 99-cluster-dns-02-config.yaml
echo "  - Updating local_openshift/99-cluster-dns-02-config.yaml..."
cat > local_openshift/99-cluster-dns-02-config.yaml << EOF
apiVersion: operator.openshift.io/v1
kind: DNS
metadata:
  name: default
spec:
  upstreamResolvers:
    policy: Sequential
    upstreams:
    - type: Network
      address: ${IP_ADDRESS}
      port: 53
EOF

# Create temporary network and dnsmasq configs
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

# Update 99-master-host-network-customizations.yaml
echo "  - Updating local_openshift/99-master-host-network-customizations.yaml..."
cat > local_openshift/99-master-host-network-customizations.yaml << EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-host-network-customizations
spec:
  config:
    ignition:
      version: 3.4.0
    passwd:
      users:
        - name: core
          passwordHash: "\$6\$jamyHU6tcWovxP.e\$rasKzY7tDn.LlazCF6Z4osY86aaXGEFOnkDSClPCw1B/DzPn2knv/kHCwncynti2r3k8MSLwcEsyEwqkDwZd8/"
    storage:
      files:


        -  path: /etc/hostname
           overwrite: true
           mode: 420
           contents:
             source: data:,${FULL_HOSTNAME}


        - path: /etc/NetworkManager/system-connections/${INTERFACE}.nmconnection
          overwrite: true
          mode:  0600
          contents:
            compression: gzip
            source: data:;base64,${NETWORK_BASE64}

        - path: /etc/NetworkManager/dnsmasq.d/ocp-sno.conf
          overwrite: true
          mode: 420
          contents:
            compression: gzip
            source: data:;base64,${DNSMASQ_BASE64}

        - path: /etc/NetworkManager/conf.d/dnsmasq.conf
          overwrite: true
          mode: 420
          contents:
            source: data:,%5Bmain%5D%0Adns%3Ddnsmasq%0A

        - path: /etc/ssh/sshd_config.d/01-password-auth.conf
          overwrite: true
          mode: 420
          contents:
            source: data:,PasswordAuthentication%20yes%0A

    systemd:
      units:
        - name: dnsmasq.service
          enabled: false
          mask: true
EOF

# Generate unsigned container policy for Voyager kernel images
echo "  - Creating local_openshift/99-master-zz-unsigned-policy.yaml..."
cat > local_openshift/99-master-zz-unsigned-policy.yaml << 'EOF'
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-zz-unsigned-policy
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - path: /etc/containers/policy.json
          mode: 420
          overwrite: true
          contents:
            compression: gzip
            source: data:;base64,H4sIAKFBf2oAA6tWUOBSAAGllNS0xNKcEiUrhehqpZLKglQgSykzrzg1ubQo1TE5ObWgxDGvsiQjMy9dqTZWB6qrpCgxr7ggv6ikGKi8GiIIFE4syc/NTAYJKRFpYK0OXHNKfnJ2ahFFmnVTElNz8/NIMgMWErVcYAIAiEOd/BoBAAA=
EOF

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
echo "  - local_openshift/99-master-zz-unsigned-policy.yaml (CRITICAL for unsigned Voyager images)"
echo ""
echo "Next steps:"
echo "  1. Verify ssh.pub and pull-secret.json files exist"
echo "  2. Copy this directory to the Fedora VM"
echo "  3. Run: VERSION=5.0 ./create_sno_iso.sh"
echo ""
