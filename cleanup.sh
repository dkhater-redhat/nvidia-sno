#!/usr/bin/env bash
set -e

echo "=========================================="
echo "Cleaning up generated files..."
echo "=========================================="

# Remove generated directories
echo "  - Removing ocp/ directory..."
rm -rf ocp/

# Remove generated ISOs (keep the downloaded RHCOS ISO)
echo "  - Removing generated ISOs..."
find . -maxdepth 1 -name "rhcos-*.iso" ! -name "rhcos-*-live-iso.aarch64.iso" -delete 2>/dev/null || true

# Remove generated ignition files
echo "  - Removing ignition files..."
rm -f *.ign

# Remove generated configs
echo "  - Removing generated configs..."
rm -f install-config.yaml
rm -f dnsmasq.bu

# Remove generated manifests in local_openshift/
echo "  - Removing generated manifests..."
rm -f local_openshift/99-cluster-dns-02-config.yaml
rm -f local_openshift/99-master-host-network-customizations.yaml
rm -f local_openshift/99-master-zz-unsigned-policy.yaml

echo ""
echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
echo ""
echo "Kept files:"
echo "  - Scripts and templates"
echo "  - ssh.pub and pull-secret.json"
echo "  - Downloaded openshift-install and RHCOS ISO"
echo "  - Source manifests (99-os-layer-custom-*.yaml)"
echo ""
echo "Next step:"
echo "  ./configure-sno.sh"
echo ""
