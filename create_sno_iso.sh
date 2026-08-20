#!/usr/bin/env bash
set -xeuo pipefail

# Set OCP version - default to 4.22, or override with VERSION env var
# Usage: VERSION=5.0 ./create_sno_iso.sh
VERSION="${VERSION:-4.22}"

case "${VERSION}" in
  "4.22")
    OCP_VERSION="4.22.0-rc.2"
    RHCOS_BUILD="10.2.20260617-0101"
    INSTALLER_URL="https://mirror.openshift.com/pub/openshift-v4/aarch64/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz"
    ;;
  "5.0")
    OCP_VERSION="5.0.0-ec.4"
    RHCOS_BUILD="10.2.20260617-0101"
    INSTALLER_URL="https://mirror.openshift.com/pub/openshift-v4/aarch64/clients/ocp-dev-preview/${OCP_VERSION}/openshift-install-linux.tar.gz"
    ;;
  *)
    echo "Error: Unsupported VERSION=${VERSION}. Supported versions: 4.22, 5.0"
    exit 1
    ;;
esac

echo "Building for OCP ${VERSION} with RHCOS ${RHCOS_BUILD}"

RHCOS_ISO="rhcos-${RHCOS_BUILD}-live-iso.aarch64.iso"


if [[ ! -x ./openshift-install ]]; then
    curl -LO "${INSTALLER_URL}"
    tar -xzf openshift-install-linux.tar.gz
    chmod +x openshift-install
fi

if [[ ! -f "${RHCOS_ISO}" ]]; then
    curl -L -O \
      "https://releases-rhcos--prod-pipeline.apps.int.prod-stable-spoke1-dc-iad2.itup.redhat.com/storage/prod/streams/rhel-10.2-ocp4nv-preview/builds/${RHCOS_BUILD}/aarch64/${RHCOS_ISO}"
fi

rm -Rf ocp
mkdir ocp


export SSH_KEY=$(cat ssh.pub | tr -d '\n\r')
export PULL_SECRET=$(cat pull-secret.json  | tr -d '\n\r')


envsubst < install-config.yaml.template > install-config.yaml

cp install-config.yaml ocp/

./openshift-install create manifests --dir ocp/

# Copy common manifests
cp local_openshift/99-cluster-dns-02-config.yaml ocp/openshift/
cp local_openshift/99-master-zz-unsigned-policy.yaml ocp/openshift/
cp local_openshift/99-master-host-network-customizations.yaml ocp/openshift/

# Copy version-specific os-layer-custom manifest
cp "local_openshift/99-os-layer-custom-${VERSION}.yaml" ocp/openshift/99-os-layer-custom.yaml

./openshift-install create single-node-ignition-config --dir ocp/

cp ocp/bootstrap-in-place-for-live-iso.ign .
butane --pretty --strict --files-dir . dnsmasq.bu -o tpm.ign
cp tpm.ign ocp/bootstrap-in-place-for-live-iso.ign 

RANDOM_ID=$(tr -dc 'a-z' </dev/urandom | head -c 5 || true)
ISO_NAME="rhcos-${RANDOM_ID}.iso"


coreos-installer iso ignition embed \
  -i ocp/bootstrap-in-place-for-live-iso.ign \
  "${RHCOS_ISO}" \
  -o "${ISO_NAME}"
