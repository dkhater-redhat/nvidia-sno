# RHCOS RHEL-10 Single Node OpenShift for Vera Rubin Testing

This repository contains automation scripts to create a bootable live ISO for Red Hat CoreOS (RHCOS) based on RHEL-10, specifically configured for Single Node OpenShift (SNO) deployment and NVIDIA GPU testing at Vera Rubin.

## Overview

The project automates the creation of a customized RHCOS live ISO for a single node that includes:
- **OpenShift Container Platform** 4.22 or 5.0 (configurable via VERSION variable)
- **RHCOS** RHEL-10.2 based builds
- **Container policy** and DNS configuration via Butane
- **Single Node OpenShift** bootstrap configuration

### Supported OCP Versions

| Version | OCP Release | RHCOS Build | Custom Image Tag |
|---------|-------------|-------------|------------------|
| 4.22 (default) | 4.22.0-rc.2 | 10.2.20260423-0102 | 4.22-10.2-ocp4nv-preview-202605082215-node-image |
| 5.0 | Latest dev-preview | 10.2.20260617-0101 | 5.0-10.2-ocp4nv-202606231810-node-image |

### RHEL-10 Configuration

The OCP 4.22 installer defaults to RHEL-9 base images, RHEL-10 is available stating in 4.23/5.0 .This project overrides the default to use RHEL-10 by setting the following in `install-config.yaml`:

```yaml
osImageStream: "rhel-10"
featureSet: TechPreviewNoUpgrade
```

### Custom OS Image

A custom node image is specified via version-specific manifests in `local_openshift/`:
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
  osImageURL: quay.io/ravanelli/nvidia/node-image:4.22-10.2-ocp4nv-preview-202605082215-node-image
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
## Quick Start

### 1. Build the ISO

Set the `VERSION` environment variable to select the OCP version (defaults to 4.22):

```bash
# For OCP 4.22 (default)
./create_sno_iso.sh

# For OCP 5.0
VERSION=5.0 ./create_sno_iso.sh
```

The VERSION variable controls which OpenShift installer, RHCOS build, and custom NVIDIA node image the script will use.

### 2. Deploy

The deployment process involves three boot phases:

#### Phase 1: Bootstrap (First Boot from ISO)

1. Mount the ISO to your target server and boot from it
2. The system will automatically:
   - Apply the ignition configuration
   - Bootstrap OpenShift
   - Reboot (no action required)

#### Phase 2: Machine Config Application (Second Boot)

1. Select the boot device from the hard drive (Samsung)
2. The Machine Config Operator will:
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

ot@vera-rubin core]# oc get co
error: Missing or incomplete configuration info.  Please point to an existing, complete config file:


  1. Via the command-line flag --kubeconfig
  2. Via the KUBECONFIG environment variable
  3. In your home directory as ~/.kube/config

To view or setup config directly use the 'config' command.

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

**Initial state (first 10-15 minutes)** - Some operators may show errors:

```bash
[core@vera-rubin ~]$ oc get co
NAME                                       VERSION      AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             5.0.0-ec.3   False       False         True       10m     APIServicesAvailable: ...bad status...401
etcd                                                    False       True          False      10m     StaticPodsAvailable: 0 nodes are active; 1 node is at revision 0...
kube-apiserver                                          False       True          False      11m     StaticPodsAvailable: 0 nodes are active; 1 node is at revision 0...
ingress                                    5.0.0-ec.3   True        True          False      10m     IngressControllerProgressing: Waiting for router deployment...
monitoring                                              Unknown     True          Unknown    9m42s   Rolling out the stack.
operator-lifecycle-manager-packageserver                False       True          False      10m     ClusterServiceVersion...phase Failed...InstallCheckFailed...install timeout
...
```

**Be patient!** The core components (CRI-O, kubelet) are still rolling out the final configuration. Monitor the cluster operators with `watch oc get co` and wait for all operators to stabilize.

**Expected final state (after 30-40 minutes)** - All operators healthy:

```bash
core@vera-rubin ~]$ oc get co
NAME                                       VERSION      AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             5.0.0-ec.3   True        False         False      2m19s
baremetal                                  5.0.0-ec.3   True        False         False      28m
cloud-controller-manager                   5.0.0-ec.3   True        False         False      28m
cloud-credential                           5.0.0-ec.3   True        False         False      49m
cluster-api                                5.0.0-ec.3   True        False         False      28m
cluster-autoscaler                         5.0.0-ec.3   True        False         False      28m
config-operator                            5.0.0-ec.3   True        False         False      28m
console                                    5.0.0-ec.3   True        False         False      2m26s
control-plane-machine-set                  5.0.0-ec.3   True        False         False      28m
csi-snapshot-controller                    5.0.0-ec.3   True        False         False      29m
dns                                        5.0.0-ec.3   True        False         False      28m
etcd                                       5.0.0-ec.3   True        False         False      18m
image-registry                             5.0.0-ec.3   True        False         False      9m49s
ingress                                    5.0.0-ec.3   True        False         False      29m
insights                                   5.0.0-ec.3   True        False         False      28m
kube-apiserver                             5.0.0-ec.3   True        False         False      10m
kube-controller-manager                    5.0.0-ec.3   True        False         False      9m47s
kube-scheduler                             5.0.0-ec.3   True        False         False      21m
kube-storage-version-migrator              5.0.0-ec.3   True        False         False      29m
machine-api                                5.0.0-ec.3   True        False         False      23m
machine-approver                           5.0.0-ec.3   True        False         False      28m
machine-config                             5.0.0-ec.3   True        False         False      22m
marketplace                                5.0.0-ec.3   True        False         False      28m
monitoring                                 5.0.0-ec.3   True        False         False      67s
network                                    5.0.0-ec.3   True        False         False      29m
node-tuning                                5.0.0-ec.3   True        False         False      23m
olm                                        5.0.0-ec.3   True        False         False      28m
openshift-apiserver                        5.0.0-ec.3   True        False         False      7m42s
openshift-controller-manager               5.0.0-ec.3   True        False         False      9m44s
openshift-samples                          5.0.0-ec.3   True        False         False      11m
operator-lifecycle-manager                 5.0.0-ec.3   True        False         False      29m
operator-lifecycle-manager-catalog         5.0.0-ec.3   True        False         False      29m
operator-lifecycle-manager-packageserver   5.0.0-ec.3   True        False         False      11m
service-ca                                 5.0.0-ec.3   True        False         False      29m
storage                                    5.0.0-ec.3   True        False         False      28m

[core@vera-rubin ~]$ oc version
Client Version: 5.0.0-202606220255.p2.g74e525a.assembly.stream-74e525a
Kustomize Version: v5.7.1
Kubernetes Version: v1.35.3

[core@vera-rubin ~]$ hostnamectl
 Static hostname: vera-rubin.nvidia.local
       Icon name: computer-server
         Chassis: server 🖳
      Machine ID: e04b7e84258e4ad98170e523896627d1
         Boot ID: 2a97323686d24236af5bc83292827e14
Operating System: Red Hat Enterprise Linux CoreOS 10.2.20260622-0 (Coughlan)
     CPE OS Name: cpe:/o:redhat:enterprise_linux:10.2
          Kernel: Linux 6.12.0-231.12.el10nv.aarch64+64k
    Architecture: arm64
 Hardware Vendor: NVIDIA
  Hardware Model: VR NVL72
Firmware Version: NV_SBIOS: 04.0A.00.00, OEM_SBIOS: 04.0A.00.00
```
### Configuration Files

- **`create_sno_iso.sh`** - Main automation script for ISO creation (supports VERSION variable)
- **`container-policy.bu`** - Butane config for container policy settings
- **`dnsmasq.bu`** - Butane config for DNS services
- **`install-config.yaml.template`** - OpenShift installation configuration template
- **`local_openshift/`** - Custom manifests for cluster configuration
  - `99-cluster-dns-02-config.yaml` - DNS configuration (common)
  - `99-master-container-policy.yaml` - Container policy (common)
  - `99-master-host-network-customizations.yaml` - Network settings (common)
  - `99-os-layer-custom-4.22.yaml` - Custom OS image for OCP 4.22
  - `99-os-layer-custom-5.0.yaml` - Custom OS image for OCP 5.0

### Version Selection

The `create_sno_iso.sh` script uses the `VERSION` environment variable to determine which OCP version to build:

| Component | VERSION=4.22 (default) | VERSION=5.0 |
|-----------|----------------------|-------------|
| Installer source | OCP stable release | OCP dev-preview latest |
| RHCOS build | 10.2.20260423-0102 | 10.2.20260617-0101 |
| Custom image manifest | 99-os-layer-custom-4.22.yaml | 99-os-layer-custom-5.0.yaml |
| Node image tag | 4.22-10.2-ocp4nv-preview-202605082215-node-image | 5.0-10.2-ocp4nv-202606231810-node-image |


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

A firmware bug prevents successful reboots, causing the system to hang with USB-related errors:

```
UsbSelectConfig: failed to connect driver - Not Found, ignored
UsbSelectConfig: failed to connect driver - Not Found, ignored
UsbSelectConfig: failed to connect driver - Not Found, ignored
UsbMassReadBlocks: UsbBootReadBlocks (Device Error) -> Reset
UsbBotExecCommand: UsbBotGetStatus (Time out)
UsbBootExecCmd: Time out to Exec 0x0 Cmd
UsbBotExecCommand: UsbBotGetStatus (Time out)
UsbBootExecCmd: Time out to Exec 0x0 Cmd
UsbMassReadBlocks: UsbBootReadBlocks (Device Error) -> Reset
UsbMassReadBlocks: UsbBootReadBlocks (Device Error) -> Reset
```

**Workaround:** This issue consistently occurs with the BMC. When encountered:
1. Restart the BMC
2. Perform a full server restart

This may need to be done multiple times throughout the deployment process.

## Additional Resources

- [OpenShift Single Node Installation Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html-single/installing_on_a_single_node/index)
- [RHCOS Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/architecture/architecture-rhcos)
- [Butane Configuration Specification](https://coreos.github.io/butane/)

