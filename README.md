# RHCOS RHEL-10 Single Node OpenShift for Vera Rubin Testing

This repository contains automation scripts to create a bootable live ISO for Red Hat CoreOS (RHCOS) based on RHEL-10, specifically configured for Single Node OpenShift (SNO) deployment and NVIDIA GPU testing at Vera Rubin.

## Overview

The project automates the creation of a customized RHCOS live ISO for a single node that includes:
- **OpenShift Container Platform** 4.22 or 5.0 (configurable via VERSION variable)
- **RHCOS** RHEL-10.2 based builds with NVIDIA Voyager kernel
- **Container policy** and DNS configuration via Butane
- **Single Node OpenShift** bootstrap configuration

### Supported OCP Versions

| Version | OCP Release | RHCOS Build | Custom Image Tag |
|---------|-------------|-------------|------------------|
| 4.22 (default) | 4.22.0-rc.2 | 10.2.20260617-0101 | 4.22-10.2-ocp4nv-preview-202606222115-node-image |
| 5.0 | 5.0.0-ec.4 | 10.2.20260617-0101 | 5.0-10.2-ocp4nv-202606231810-node-image |

### RHEL-10 Configuration

The OCP 4.22 installer defaults to RHEL-9 base images. RHEL-10 is available starting in 4.23/5.0. This project overrides the default to use RHEL-10 by setting the following in `install-config.yaml`:

```yaml
osImageStream: "rhel-10"
featureSet: TechPreviewNoUpgrade
```

### Custom OS Image for NVIDIA Voyager Kernel

A custom node image with NVIDIA Voyager kernel is specified via version-specific manifests in `local_openshift/`:
- `99-os-layer-custom-4.22.yaml` - For OCP 4.22
- `99-os-layer-custom-5.0.yaml` - For OCP 5.0

Instead of doing the off-cluster layering to use the right image, we are already doing it as part of Day 0.

Example for OCP 4.22:
```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: os-layer-custom
spec:
  osImageURL: quay.io/ravanelli/nvidia/node-image:4.22-10.2-ocp4nv-preview-202606222115-node-image
```

Example for OCP 5.0:
```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: os-layer-custom
spec:
  osImageURL: quay.io/ravanelli/nvidia/node-image:5.0-10.2-ocp4nv-202606231810-node-image
```

**Note:** This uses a personal repository (`quay.io/ravanelli/nvidia`) because the custom image is not yet part of the official OCP payload, and OpenShift would otherwise reject unsigned images.

## Prerequisites

Before running the setup script, ensure you have the following tools installed:

### Required Tools

1. **Butane** - Configuration translator for CoreOS systems
   ```bash
   # Download butane for your platform
   https://github.com/coreos/butane/releases
   ```

2. **coreos-installer** - Tool for installing CoreOS
   ```bash
   # Download from:
   https://github.com/coreos/coreos-installer/releases
   ```

### Required Files

* `ssh.pub` - Your SSH public key for node access
* `pull-secret.json` - Red Hat pull secret from console.redhat.com

## Deployment Guide

### Step 1: Configure Deployment Files

Run the interactive configuration script:

```bash
./configure-sno.sh
```

The script will prompt you for network and system configuration and update all configuration files using targeted sed replacements.

### Step 2: Build the ISO

Set the `VERSION` environment variable to select the OCP version (defaults to 4.22):

```bash
# For OCP 4.22 (default)
./create_sno_iso.sh

# For OCP 5.0
VERSION=5.0 ./create_sno_iso.sh
```

**Version Selection:**

The `VERSION` environment variable controls which OpenShift installer, RHCOS build, and custom NVIDIA node image the script will use:

| Version | OCP Release | RHCOS Build | Custom Image Tag |
|---------|-------------|-------------|------------------|
| 4.22 (default) | 4.22.0-rc.2 | 10.2.20260617-0101 | 4.22-10.2-ocp4nv-preview-202606222115-node-image |
| 5.0 | 5.0.0-ec.4 | 10.2.20260617-0101 | 5.0-10.2-ocp4nv-202606231810-node-image |

The script will:
* Download openshift-install for the selected OCP version
* Download RHCOS 10.2 with NVIDIA Voyager kernel
* Generate manifests and ignition configs (including the appropriate os-layer-custom manifest)
* Embed ignition into the ISO
* Create a bootable ISO named `rhcos-xxxxx.iso` (random ID)

### Step 3: Deploy

The deployment process involves three boot phases:

#### Phase 1: Bootstrap (First Boot from ISO)

1. Mount the ISO to your target server via BMC virtual media and boot from it
2. The system will automatically:
   - Apply the ignition configuration
   - Bootstrap OpenShift
   - Reboot (no action required)

#### Phase 2: Machine Config Application (Second Boot)

1. Unmount the ISO in BMC before reboot
2. Boot from hard drive (the disk you specified)
3. Select the RHCOS entry in GRUB
4. The Machine Config Operator will:
   - Apply the cluster configurations
   - Automatically reboot (no action required)

#### Phase 3: Cluster Initialization (Third Boot)

1. Select the RHCOS installation from the boot menu
   - You should see 2 OSTree deployments available
2. Wait for the cluster to become ready
   - **OCP 4.22**: ~18-20 minutes
   - **OCP 5.0**: ~30-40 minutes (see note below)

#### Accessing the Cluster

Initial access using the bootstrap kubeconfig:
```bash
export KUBECONFIG=/etc/kubernetes/bootstrap-secrets/kubeconfig
oc get nodes
```

Expected output:
```bash
[root@vera-rubin core]# oc get nodes
NAME                      STATUS   ROLES                         AGE   VERSION
vera-rubin.nvidia.local   Ready    control-plane,master,worker   18m   v1.35.3
```

Check cluster operator status:
```bash
[root@vera-rubin core]# oc get co
NAME                                       VERSION       AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.22.0-rc.5   True        False         False      3m20s
baremetal                                  4.22.0-rc.5   True        False         False      17m
cloud-controller-manager                   4.22.0-rc.5   True        False         False      14m
cloud-credential                           4.22.0-rc.5   True        False         False      15m
cluster-api                                4.22.0-rc.5   True        False         False      17m
cluster-autoscaler                         4.22.0-rc.5   True        False         False      14m
config-operator                            4.22.0-rc.5   True        False         False      17m
console                                    4.22.0-rc.5   True        False         False      3m35s
control-plane-machine-set                  4.22.0-rc.5   True        False         False      16m
csi-snapshot-controller                    4.22.0-rc.5   True        False         False      17m
dns                                        4.22.0-rc.5   True        False         False      16m
etcd                                       4.22.0-rc.5   True        False         False      15m
image-registry                             4.22.0-rc.5   True        False         False      5m8s
ingress                                    4.22.0-rc.5   True        False         False      17m
insights                                   4.22.0-rc.5   True        False         False      14m
kube-apiserver                             4.22.0-rc.5   True        False         False      6m34s
kube-controller-manager                    4.22.0-rc.5   True        False         False      8m43s
kube-scheduler                             4.22.0-rc.5   True        False         False      10m
kube-storage-version-migrator              4.22.0-rc.5   True        False         False      17m
machine-api                                4.22.0-rc.5   True        False         False      14m
machine-approver                           4.22.0-rc.5   True        False         False      14m
machine-config                             4.22.0-rc.5   True        False         False      16m
marketplace                                4.22.0-rc.5   True        False         False      17m
monitoring                                               Unknown     True          Unknown    17m     Rolling out the stack.
network                                    4.22.0-rc.5   True        False         False      17m
node-tuning                                4.22.0-rc.5   True        False         False      16m
olm                                        4.22.0-rc.5   True        False         False      16m
openshift-apiserver                        4.22.0-rc.5   True        False         False      3m43s
openshift-controller-manager               4.22.0-rc.5   True        False         False      5m13s
openshift-samples                          4.22.0-rc.5   True        False         False      3m28s
operator-lifecycle-manager                 4.22.0-rc.5   True        False         False      17m
operator-lifecycle-manager-catalog         4.22.0-rc.5   True        False         False      17m
operator-lifecycle-manager-packageserver   4.22.0-rc.5   True        False         False      6m47s
service-ca                                 4.22.0-rc.5   True        False         False      17m
storage                                    4.22.0-rc.5   True        False         False      17m
```

After the cluster is fully initialized, the bootstrap kubeconfig will stop working. Switch to the permanent kubeconfig:

```bash
[root@vera-rubin core]# export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
[root@vera-rubin core]# oc get co
NAME                                       VERSION       AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.22.0-rc.5   True        False         False      8m5s
baremetal                                  4.22.0-rc.5   True        False         False      21m
cloud-controller-manager                   4.22.0-rc.5   True        False         False      19m
cloud-credential                           4.22.0-rc.5   True        False         False      19m
cluster-api                                4.22.0-rc.5   True        False         False      22m
cluster-autoscaler                         4.22.0-rc.5   True        False         False      19m
config-operator                            4.22.0-rc.5   True        False         False      22m
console                                    4.22.0-rc.5   True        False         False      8m20s
control-plane-machine-set                  4.22.0-rc.5   True        False         False      21m
csi-snapshot-controller                    4.22.0-rc.5   True        False         False      22m
dns                                        4.22.0-rc.5   True        False         False      21m
etcd                                       4.22.0-rc.5   True        False         False      20m
image-registry                             4.22.0-rc.5   True        False         False      9m53s
ingress                                    4.22.0-rc.5   True        False         False      21m
insights                                   4.22.0-rc.5   True        False         False      19m
kube-apiserver                             4.22.0-rc.5   True        False         False      11m
kube-controller-manager                    4.22.0-rc.5   True        False         False      13m
kube-scheduler                             4.22.0-rc.5   True        False         False      15m
kube-storage-version-migrator              4.22.0-rc.5   True        False         False      22m
machine-api                                4.22.0-rc.5   True        False         False      19m
machine-approver                           4.22.0-rc.5   True        False         False      19m
machine-config                             4.22.0-rc.5   True        False         False      20m
marketplace                                4.22.0-rc.5   True        False         False      22m
monitoring                                 4.22.0-rc.5   True        False         False      2m47s
network                                    4.22.0-rc.5   True        False         False      22m
node-tuning                                4.22.0-rc.5   True        False         False      21m
olm                                        4.22.0-rc.5   True        False         False      21m
openshift-apiserver                        4.22.0-rc.5   True        False         False      8m28s
openshift-controller-manager               4.22.0-rc.5   True        False         False      9m58s
openshift-samples                          4.22.0-rc.5   True        False         False      8m13s
operator-lifecycle-manager                 4.22.0-rc.5   True        False         False      21m
operator-lifecycle-manager-catalog         4.22.0-rc.5   True        False         False      21m
operator-lifecycle-manager-packageserver   4.22.0-rc.5   True        False         False      11m
service-ca                                 4.22.0-rc.5   True        False         False      22m
storage                                    4.22.0-rc.5   True        False         False      22m
```

All operators should show `AVAILABLE=True` and `DEGRADED=False`. The monitoring operator may show `PROGRESSING=True` initially while rolling out, after changing to the right kubeconfig, it should be also ok.

### OCP 5.0 Initialization Behavior

**Note for OCP 5.0 deployments:** The cluster initialization takes significantly longer (~30-40 minutes total) compared to OCP 4.22. During the initial phase, you may observe several cluster operators in a degraded or progressing state.

**Be patient!** The core components (CRI-O, kubelet) are still rolling out the final configuration. Monitor the cluster operators with `watch oc get co` and wait for all operators to stabilize.

---

## Known Issues

### 1. Disk Cleanup Required Before Installation

Due to disk issues encountered during setup, it may be necessary to clean up older installations before starting the process:

```bash
for d in /dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1; do
    echo "Cleaning $d"
    sudo wipefs -a "$d"
done
```

### 2. BMC Firmware Reboot Bug

A firmware bug prevents successful reboots, causing the system to hang with USB-related errors. This issue consistently occurs with the BMC.

**Workaround:** When encountered:
1. Restart the BMC
2. Perform a full server restart

This may need to be done multiple times throughout the deployment process.

---

# Post-Deployment Operations

## Upgrading NVIDIA Voyager Kernel

Check available Voyager kernel releases at:
https://releases-rhcos--prod-pipeline.apps.int.prod-stable-spoke1-dc-iad2.itup.redhat.com/?stream=prod/streams/rhel-10.2-ocp4nv&arch=aarch64

### Standalone Kernel Upgrade

```bash
# Example: Upgrade to July 2026 Voyager kernel (6.12.0-250.17)
cat <<EOF | oc apply -f -
   apiVersion: machineconfiguration.openshift.io/v1
   kind: MachineConfig                            
   metadata:
     labels:
       machineconfiguration.openshift.io/role: master
     name: os-layer-custom
   spec:
     osImageURL: quay.io/openshift-release-dev/ocp-v4.0-art-dev:5.0-10.2-ocp4nv-202607211530-node-image
EOF
```

```bash
oc get mcp -w
```

The node will:
* Pull the new kernel image
* Update UPDATING to True
* Cordone and drain
* Reboot with the new kernel
* Show UPDATED: True when complete

## Combined OCP and Kernel Upgrade

You can upgrade both OpenShift and the Voyager kernel in a single reboot.

### Current State Example
* OCP: 5.0.0-ec.4
* Kernel: 6.12.0-231.12 (June - 202606231810)

### Target State Example
* OCP: 5.0.0-ec.5
* Kernel: 6.12.0-250.17 (July - 202607211530)

### Upgrade Process

**Step 1:** Check available OCP upgrade
```bash
oc adm upgrade
```

**Step 2:** Pause the master MachineConfigPool (prevents immediate reboot)
```bash
oc patch mcp master --type merge --patch '{"spec":{"paused":true}}'
oc get mcp master -o jsonpath='{.spec.paused}'
```
Verify it shows `true`

**Step 3:** Update the osImageURL to the new kernel image
```bash
oc patch machineconfig os-layer-custom --type merge --patch \
  '{"spec":{"osImageURL":"quay.io/openshift-release-dev/ocp-v4.0-art-dev:5.0-10.2-ocp4nv-202607211530-node-image"}}'
```

**Step 4:** Verify the patch
```bash
oc get mc os-layer-custom -o yaml | grep osImageURL
```

**Step 5:** Start the OCP upgrade
```bash
oc adm upgrade --to=5.0.0-ec.5 --force --allow-explicit-upgrade --allow-upgrade-with-warnings
```
Note: `--force` and `--allow-explicit-upgrade` may be needed for dev preview versions

**Step 6:** Verify the upgrade started
```bash
oc get clusterversion
```
Should show PROGRESSING: True

**Step 7:** Unpause the master MachineConfigPool (triggers the combined upgrade)
```bash
oc patch mcp master --type merge --patch '{"spec":{"paused":false}}'
oc get mcp master
```

**Step 8:** Monitor the upgrade progress

Watch MachineConfigPool:
```bash
oc get mcp -w
```

Watch ClusterVersion:
```bash
oc get clusterversion -w
```

Watch cluster operators:
```bash
watch oc get co
```

### Upgrade Timeline

The node will:
1. Generate a new rendered-master config (combines ec.5 + new kernel)
2. Cordone and drain the node
3. Apply both OCP ec.5 updates AND kernel upgrade
4. Reboot once
5. Come back with both upgrades applied

Total time: 15-30 minutes with one reboot

### Verification

After upgrade completes:

```bash
# Verify OCP version
oc get clusterversion

# Verify all operators
oc get co

# Verify kernel version
ssh core@<node-ip> uname -r

# Verify RHCOS image
ssh core@<node-ip> sudo rpm-ostree status
```

All cluster operators should show:
* VERSION: 5.0.0-ec.5 (or your target version)
* AVAILABLE: True
* PROGRESSING: False
* DEGRADED: False

---

## Configuration Files

- **`configure-sno.sh`** - Interactive configuration script (updates existing files via sed)
- **`create_sno_iso.sh`** - Main automation script for ISO creation (supports VERSION variable)
- **`dnsmasq.bu`** - Butane config for DNS services
- **`install-config.yaml.template`** - OpenShift installation configuration template
- **`local_openshift/`** - Custom manifests for cluster configuration
  - `99-cluster-dns-02-config.yaml` - DNS configuration
  - `99-master-zz-unsigned-policy.yaml` - Container policy for unsigned Voyager images
  - `99-master-host-network-customizations.yaml` - Network settings
  - `99-os-layer-custom-4.22.yaml` - Custom OS image for OCP 4.22
  - `99-os-layer-custom-5.0.yaml` - Custom OS image for OCP 5.0

## Appendix: Hardware Verification

If you need to identify hardware specifications before running `configure-sno.sh`, boot into an existing RHEL system on the target node:

```bash
# Identify network interface
ip addr
nmcli device status

# Identify boot disk
lsblk
ls -l /dev/disk/by-id/ | grep nvme

# Test network connectivity
ping -c 3 <gateway-ip>
ping -c 3 8.8.8.8
```

Record the following:
* Network interface name (e.g., enP5p65s0f0np0)
* IP address, subnet mask (CIDR), and gateway
* Disk ID (e.g., nvme-eui.385348304c3072860025384700000001)
* Hostname and domain

