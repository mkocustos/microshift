#!/usr/bin/env bash
#
# Checks a COPR repository built by copr-stable.yaml from inside a clean
# Fedora container: the packages of one OpenShift version resolve against the
# OpenShift mirror, carry no OKD image references, and their release info
# names exactly the images of the OpenShift payload of that version.
#
# Usage: verify-stable-repo.sh <copr-owner/project> <ocp-version>
#
set -euxo pipefail

COPR_REPO_NAME="$1"
OCP_VERSION="$2"
OCP_MIRROR_URL="https://mirror.openshift.com/pub/openshift-v4"
OCP_RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release"

dnf install -y dnf-plugins-core cpio jq
dnf copr enable -y "${COPR_REPO_NAME}"
dnf install -y microshift-io-dependencies

# The version this run is about must be in the repository, not necessarily as
# the newest one: rebuilding an older release as a way back is legitimate.
version_re="^${OCP_VERSION//./\\.}_.*_ocp_${OCP_VERSION//./\\.}\$"
version="$(dnf repoquery --queryformat '%{version}\n' \
              --disablerepo='*' --enablerepo='*microshift-stable*' microshift \
            | grep -E "${version_re}" | sort -V | tail -1 || true)"
echo "microshift in the repository: ${version}"
[ -n "${version}" ]

# Resolve and download the full package set without running the scriptlets,
# which need a real system.
pkgs=(microshift microshift-greenboot microshift-selinux microshift-kindnet
      microshift-release-info microshift-kindnet-release-info)
# dnf5 knows --destdir only for 'download', so resolve first, then fetch the
# packages themselves for inspection.
dnf install -y --downloadonly "${pkgs[@]/%/-${version}}"
dnf download --destdir /tmp/rpms "${pkgs[@]/%/-${version}}"

mkdir /tmp/x
cd /tmp/x
for rpm in /tmp/rpms/microshift-*"${version}"*.rpm; do
    rpm2cpio "${rpm}" | cpio -idm --quiet
done

if grep -ra -l "quay.io/okd/" . ; then
    echo "ERROR: OKD image references left in the packages" >&2
    exit 1
fi

# Every image of the release info must be the one the payload names.
# lvms_operator is not part of the payload and stays as upstream ships it.
curl -fsSL --retry 5 \
    "${OCP_MIRROR_URL}/x86_64/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz" \
    | tar -xz -C /usr/local/bin oc
oc adm release info "${OCP_RELEASE_IMAGE}:${OCP_VERSION}-x86_64" -o json \
    | jq -r '.references.spec.tags[] | "\(.name) \(.from.name)"' | sort > /tmp/payload.txt
jq -r '.images | to_entries[] | select(.key != "lvms_operator") | "\(.key) \(.value)"' \
    usr/share/microshift/release/release-x86_64.json \
    usr/share/microshift/release/release-kube-proxy-x86_64.json | sort > /tmp/release.txt
cat /tmp/release.txt
[ -s /tmp/release.txt ]
if comm -23 /tmp/release.txt /tmp/payload.txt | grep . ; then
    echo "ERROR: the images above do not match the ${OCP_VERSION} payload" >&2
    exit 1
fi
echo "OK: ${version} carries the images of OpenShift ${OCP_VERSION}"
