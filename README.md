# NVIDIA Grace SNO Deployment Guide

## Phase 1: Verify Hardware Configuration

1. Boot into existing RHEL system on target node (to identify correct hardware specs)
   ```bash
   # Login via SOL console or SSH
   ```

2. Identify the correct network interface
   ```bash
   ip addr
   ip route
   nmcli device status
   ```
   * Record the interface name that has your IP (e.g., enP5p65s0f0np0)
   * Note the IP address, subnet mask, and gateway

3. Identify the correct boot disk
   ```bash
   lsblk
   ls -l /dev/disk/by-id/ | grep nvme
   ```
   * Find the disk-by-id for your boot disk (e.g., nvme-eui.385348304c3072860025384700000001)
   * Verify it shows the correct boot partitions (/boot/efi, /boot, /)

4. Test network connectivity
   ```bash
   ping -c 3 <gateway-ip>  # Gateway (may not respond but routing works)
   ping -c 3 8.8.8.8       # Internet connectivity test
   ```

5. Record hostname and domain
   ```bash
   hostname
   ```

## Phase 2: Configure and Build ISO

1. On your Mac (or build machine), navigate to the project directory
   ```bash
   cd nvidia-sno-with-upgrade
   ```

2. Ensure you have the required files:
   ```bash
   ls ssh.pub pull-secret.json
   ```
   * `ssh.pub` - Your SSH public key for node access
   * `pull-secret.json` - Red Hat pull secret from console.redhat.com

3. Run the configuration script
   ```bash
   ./configure-sno.sh
   ```
   Enter the values you recorded in Phase 1:
   * IP address
   * Subnet mask (CIDR notation, e.g., 28 for /28)
   * Gateway
   * Primary and secondary DNS servers
   * Network interface name
   * Disk ID (without /dev/disk/by-id/ prefix)
   * Hostname (short name, e.g., vera-rubin)
   * Domain (e.g., nvidia.local)

   The script will generate all required configuration files.

4. Build the SNO ISO for OCP 5.0
   ```bash
   VERSION=5.0 ./create_sno_iso.sh
   ```
   This will:
   * Download openshift-install for OCP 5.0.0-ec.4
   * Download RHCOS 10.2 with NVIDIA Voyager kernel
   * Generate manifests and ignition configs
   * Embed ignition into the ISO
   * Create a bootable ISO named `rhcos-xxxxx.iso` (random ID)

## Phase 3: Deploy to Target Node

1. Mount ISO via BMC virtual media
   * Login to BMC web interface
   * Navigate to Virtual Media
   * Mount the `rhcos-xxxxx.iso` file
   * Note: You may need to copy the ISO to a location accessible by the BMC

2. Reboot and boot from ISO
   * Reboot the node
   * Select USB1/Virtual Media in the boot menu
   * System will boot from the ISO

3. Wait for Phase 1: Bootstrap to complete (20-30 minutes)
   * Watch console logs
   * Wait for "bootkube.service complete" message
   * System will schedule reboot in 1 minute

4. Unmount ISO in BMC before reboot
   * Remove virtual media to prevent booting from ISO again

5. Let system reboot into Phase 2: Machine Config Application
   * Boot from hard drive (the disk you specified)
   * Select RHCOS entry in GRUB
   * MCO applies configurations
   * System automatically reboots again

6. System boots into Phase 3: Cluster Initialization (30-40 minutes)
   * Boot shows: "Red Hat Enterprise Linux CoreOS 10.2" with NVIDIA Voyager kernel
   * Wait for cluster initialization
   * Console will show container activity (normal to see lots of crio-* services)

## Phase 4: Verify Deployment

1. SSH into the node or use console
   ```bash
   ssh core@<node-ip>
   # OR login via SOL console
   ```

2. Check cluster status
   ```bash
   sudo -i
   
   # During bootstrap phase:
   export KUBECONFIG=/etc/kubernetes/bootstrap-secrets/kubeconfig
   
   # After bootstrap completes:
   export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
   
   oc get nodes
   oc get co
   ```

3. Verify all cluster operators are Available
   * All should show: AVAILABLE=True, PROGRESSING=False, DEGRADED=False
   * May take full 30-40 minutes for OCP 5.0 to stabilize

4. Verify kernel version
   ```bash
   uname -r
   # Should show NVIDIA Voyager kernel (e.g., 6.12.0-231.12 for June release)
   
   rpm-ostree status
   # Should show the RHCOS image with ocp4nv build
   ```

---

## Example Configuration Values (Vera Rubin)

These are example values - use your actual hardware specifications:

* **IP:** 10.28.128.22/28
* **Gateway:** 10.28.128.17
* **DNS:** 103.247.36.36, 8.8.8.8
* **Interface:** enP5p65s0f0np0
* **Disk:** nvme-eui.385348304c3072860025384700000001
* **Hostname:** vera-rubin
* **Domain:** nvidia.local
* **Full FQDN:** vera-rubin.nvidia.local
* **Network CIDR:** 10.28.128.16/28

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

## License

OpenShift is licensed under the Apache Public License 2.0. The source code for this
program is [located on github](https://github.com/openshift/installer).
