# Using Fedora for easy access to the dependencies (no need to install EPEL or use pip)
FROM quay.io/fedora/fedora:latest

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        git rpm-build jq python3-pip python3-specfile skopeo && \
    dnf clean all

# Variables controlling the source of MicroShift components to build
ARG USHIFT_GITREF=main
ARG OKD_VERSION_TAG
# Optional OKD x.y stream (e.g. '4.22'). It pins the auto-detected cross-arch
# OKD version to the same stream as OKD_VERSION_TAG. Empty means latest.
ARG OKD_VERSION_STREAM=
# Optional OpenShift release (e.g. '4.22.20'). When set, the component images
# come from the official OpenShift release payload of exactly that version
# instead of OKD, and OKD_VERSION_TAG / OKD_VERSION_STREAM are ignored. The
# payload metadata is public; pulling the component images needs a Red Hat
# pull secret on the host (/etc/crio/openshift-pull-secret), not here.
ARG OCP_VERSION=

# Internal variables
ARG OKD_RELEASE_IMAGE_X86_64=quay.io/okd/scos-release
ARG OKD_RELEASE_IMAGE_AARCH64=ghcr.io/microshift-io/okd/okd-release-arm64
ARG OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release
ARG OCP_MIRROR_URL=https://mirror.openshift.com/pub/openshift-v4
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV HOME=/home/microshift
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh
ARG USHIFT_BUILDRPMS_SCRIPT=/tmp/build-rpms.sh
ARG OKD_GET_VERSION_SCRIPT=/tmp/get_version.sh
ARG USHIFT_MODIFY_SPEC_SCRIPT=/tmp/modify-spec.py
ARG SPEC_KINDNET=/tmp/kindnet.spec
ARG SPEC_TOPOLVM=/tmp/topolvm.spec
ARG LVMD_CONFIG_SCRIPT=/tmp/prepare_lvmd_config.sh
ARG VG_NAME
ARG SPARE_GB

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ] && [ -z "${OCP_VERSION}" ]; then \
        echo "ERROR: neither OKD_VERSION_TAG nor OCP_VERSION is set"; \
        echo "See quay.io/okd/scos-release for a list of OKD tags"; \
        exit 1; \
    fi

# Resolve the per-architecture release payload (image and tag) and the label
# that ends up in the RPM version.
# OKD: OKD_VERSION_TAG is for the host arch; the cross-arch version is
# auto-detected within the same OKD stream when OKD_VERSION_STREAM is set.
# Without the pin, a release branch build would embed release images of the
# newest OKD stream for the other architecture.
# OCP: both architectures are published under the same version, so there is
# nothing to detect.
COPY --chmod=755 ./src/okd/get_version.sh ${OKD_GET_VERSION_SCRIPT}
RUN if [ -n "${OCP_VERSION}" ]; then \
        echo "${OCP_RELEASE_IMAGE}" > /tmp/release_image_x86_64 ; \
        echo "${OCP_RELEASE_IMAGE}" > /tmp/release_image_aarch64 ; \
        echo "${OCP_VERSION}-x86_64"  > /tmp/okd_version_x86_64 ; \
        echo "${OCP_VERSION}-aarch64" > /tmp/okd_version_aarch64 ; \
        echo "ocp-${OCP_VERSION}" > /tmp/release_label ; \
    else \
        echo "${OKD_RELEASE_IMAGE_X86_64}"  > /tmp/release_image_x86_64 ; \
        echo "${OKD_RELEASE_IMAGE_AARCH64}" > /tmp/release_image_aarch64 ; \
        echo "${OKD_VERSION_TAG}" > /tmp/release_label ; \
        if [ "$(uname -m)" = "aarch64" ]; then \
            echo "${OKD_VERSION_TAG}" > /tmp/okd_version_aarch64 ; \
            "${OKD_GET_VERSION_SCRIPT}" latest-amd64 "${OKD_VERSION_STREAM}" > /tmp/okd_version_x86_64 ; \
        else \
            echo "${OKD_VERSION_TAG}" > /tmp/okd_version_x86_64 ; \
            "${OKD_GET_VERSION_SCRIPT}" latest-arm64 "${OKD_VERSION_STREAM}" > /tmp/okd_version_aarch64 ; \
        fi ; \
    fi && \
    echo "Release x86_64:  $(cat /tmp/release_image_x86_64):$(cat /tmp/okd_version_x86_64)" && \
    echo "Release aarch64: $(cat /tmp/release_image_aarch64):$(cat /tmp/okd_version_aarch64)" && \
    echo "Release label:   $(cat /tmp/release_label)"

RUN [ "$(uname -m)" = "aarch64" ] && ARCH="-arm64" || ARCH="" ; \
    if [ -n "${OCP_VERSION}" ]; then \
        CLIENT_URL="${OCP_MIRROR_URL}/$(uname -m)/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz" ; \
    else \
        CLIENT_URL="https://github.com/okd-project/okd/releases/download/${OKD_VERSION_TAG}/openshift-client-linux${ARCH}-${OKD_VERSION_TAG}.tar.gz" ; \
    fi && \
    echo "CLIENT_URL: ${CLIENT_URL}" && \
    curl -fsSL --retry 5 -o /tmp/okd-client.tar.gz "${CLIENT_URL}" && \
    tar -xzf /tmp/okd-client.tar.gz -C /usr/local/bin/ && \
    rm -rf /tmp/okd-client.tar.gz

WORKDIR ${HOME}

RUN git clone --branch "${USHIFT_GITREF}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift"

# Replace component images with OKD image references
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}
RUN ARCH="x86_64"  "${USHIFT_PREBUILD_SCRIPT}" --replace "$(cat /tmp/release_image_x86_64)"  "$(cat /tmp/okd_version_x86_64)" && \
    ARCH="aarch64" "${USHIFT_PREBUILD_SCRIPT}" --replace "$(cat /tmp/release_image_aarch64)" "$(cat /tmp/okd_version_aarch64)"

WORKDIR ${HOME}/microshift/

COPY ./src/kindnet/kindnet.spec "${SPEC_KINDNET}"
COPY ./src/kindnet/assets/  ./assets/optional/
COPY ./src/kindnet/dropins/ ./packaging/kindnet/
COPY ./src/kindnet/crio.conf.d/ ./packaging/crio.conf.d/

COPY ./src/topolvm/topolvm.spec "${SPEC_TOPOLVM}"
COPY ./src/topolvm/assets/  ./assets/optional/topolvm/
COPY ./src/topolvm/dropins/ ./packaging/microshift/dropins/
COPY ./src/topolvm/greenboot/ ./packaging/greenboot/
COPY ./src/topolvm/release/ ./assets/optional/topolvm/
COPY --chmod=755 ./src/topolvm/prepare_lvmd_config.sh ${LVMD_CONFIG_SCRIPT}
RUN ${LVMD_CONFIG_SCRIPT} ./packaging/topolvm/lvmd.yaml "${VG_NAME}" "${SPARE_GB}" && \
    rm -f ${LVMD_CONFIG_SCRIPT}

RUN ARCH="x86_64"  "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "$(cat /tmp/release_image_x86_64)"  "$(cat /tmp/okd_version_x86_64)" && \
    ARCH="aarch64" "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "$(cat /tmp/release_image_aarch64)" "$(cat /tmp/okd_version_aarch64)" && \
    ARCH="x86_64"  "${USHIFT_PREBUILD_SCRIPT}" --replace-multus  "$(cat /tmp/release_image_x86_64)"  "$(cat /tmp/okd_version_x86_64)" && \
    ARCH="aarch64" "${USHIFT_PREBUILD_SCRIPT}" --replace-multus  "$(cat /tmp/release_image_aarch64)" "$(cat /tmp/okd_version_aarch64)"

COPY --chmod=755 ./src/image/modify-spec.py ${USHIFT_MODIFY_SPEC_SCRIPT}
# Disable the RPM and SRPM checks in the make-rpm.sh script
# and modify the microshift.spec to remove packages not yet supported by the upstream
RUN sed -i -e 's,CHECK_RPMS="y",,g' -e 's,CHECK_SRPMS="y",,g' ./packaging/rpm/make-rpm.sh && \
    "${USHIFT_MODIFY_SPEC_SCRIPT}" ./packaging/rpm/microshift.spec "${SPEC_KINDNET}" "${SPEC_TOPOLVM}"

COPY --chmod=755 ./src/image/build-rpms.sh ${USHIFT_BUILDRPMS_SCRIPT}
ARG BUILD_TIMESTAMP
RUN OKD_VERSION_TAG="$(cat /tmp/release_label)" "${USHIFT_BUILDRPMS_SCRIPT}" srpm
