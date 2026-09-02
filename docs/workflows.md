## GitHub Workflows

The GitHub Workflows are defined at the `.github/workflows` folder, including
pre-submit tests and software release procedures.

* Pre-submit tests are run automatically before a pull request can be merged
* Software release procedures can be run under the [Actions](https://github.com/microshift-io/microshift/actions)
  tab by the repository maintainers, or scheduled for regular automatic execution

> Note: Contributors can create a fork from the [MicroShift Upstream](https://github.com/microshift-io/microshift)
> repository and run software release workflows in their private repository branches.

The remainder of this document describes the existing workflows and their functionality.

### Pre-submit Workflows

The workflows described in this section are run as a prerequisite for merging a
pull request into the main branch. If any of these procedures exit with errors,
the pull request cannot be merged before all the errors are fixed.

#### Builders

Build a MicroShift Bootc image from the `main` MicroShift source branch and the
latest published OKD version tag. Run this image to verify that all the MicroShift
services are functional.

The following operating systems are tested:
* Fedora, CentOS 9 and CentOS 10 for RPM packages and Bootc images
* Ubuntu for DEB packages

The following configurations are tested:
* The `x86_64` and `aarch64` architectures
* Isolated network for OVN-K and Kindnet CNI

#### Installers

Run the [Quick Start](../README.md#quick-start) procedures to verify:
* The latest published RPM packages on the supported operating systems and
  architectures
* The latest published Bootc images on the supported architectures

The [quick clean](./quickclean.sh) script is called in the end to verify the
uninstall procedure.

#### Linters

Run [ShellCheck](https://github.com/koalaman/shellcheck) on all shell scripts and
[hadolint](https://github.com/hadolint/hadolint) on all container files in the repository.

### Software Release Procedures

#### MicroShift

The workflow implements a build process producing MicroShift RPM packages, DEB
packages and Bootc container image artifacts. It is executed manually by the
repository maintainers - no scheduled runs are configured at this time.

The following parameters determine the MicroShift source code branch and the OKD
container image dependencies used during the build process.
* [MicroShift (OpenShift) branch](https://github.com/openshift/microshift/branches)
* [OKD version tag](https://quay.io/repository/okd/scos-release?tab=tags)

The following actions are supported:
* `packages`: Build MicroShift RPM and DEB packages
* `bootc-image`: Build a MicroShift Bootc container image
* `all`: Build all of the above

> Note: After the Bootc container image is built, a workflow step checks it by
> attempting to run the container image and verifying that all the MicroShift
> services are functional.

If the build job finishes successfully, the artifact download and installation
instructions are available at [Releases](https://github.com/microshift-io/microshift/releases).

> Note: The available container images can be listed at [Packages](https://github.com/microshift-io/microshift/packages)
> and pulled from the `ghcr.io/microshift-io` registry.

#### OKD on ARM

The workflow implements a build process producing a subset of OKD container image
artifacts that are required by MicroShift on the `aarch64` architecture. It runs
every day at 03:00 UTC to make sure ARM artifacts are available for the latest
OKD releases.

> Note: OKD `aarch64` builds are performed using MicroShift-specific build procedure
> until [OKD Build of OpenShift on Arm](https://issues.redhat.com/browse/OKD-215)
> is implemented by the OKD team.

The following parameters determine the MicroShift source code branch and the OKD
container image dependencies used during the build process.
* [MicroShift (OpenShift) branch](https://github.com/openshift/microshift/branches)
* [OKD version tag](https://quay.io/repository/okd/scos-release?tab=tags)

The default target registry for publishing OKD container image artifacts is
`ghcr.io/microshift-io/okd`.

> Note: After the OKD container images are built, a workflow step checks them by
> creating a MicroShift Bootc image with the new artifacts, attempting to run it,
> and verifying that all the MicroShift services work.

If the build job finishes successfully, the available container images can be listed
at [Packages](https://github.com/microshift-io/microshift/packages) and pulled from
the `ghcr.io/microshift-io` registry.

#### Private 4.y Nightly

> Note: This workflow (`copr-nightly-4x.yaml`) is not part of the upstream
> pipeline. It exists because the upstream nightly only builds what
> @microshift-io publishes, while a 4.y stream needs a COPR project that only a
> project admin can create. It pushes into a COPR project owned by the fork owner
> instead, reusing the very same make targets.

The workflow builds the newest `release-4.y` branch of MicroShift for which an
OKD payload exists on both architectures, every day at 02:00 UTC. Two behaviours
differ from the upstream nightly on purpose.

**The OKD payload is resolved from amd64.** The `okd-version` action queries the
self-built arm64 mirror by default, because that mirror is normally the limiting
factor and pinning both architectures to the same tag keeps them consistent. That
breaks down for a *pinned release stream*: the mirror follows the newest OKD
stream and stops rebuilding a stream once it has branched, so 4.22 ends there at
`ec.16` (8 May 2026) while quay.io has published releases well past it. Since
`get_version.sh` prefers released tags and finds none, it falls back to that old
EC indefinitely. The workflow therefore passes `check-amd64: "true"`.

This is only sound because the target COPR project has x86_64 chroots
exclusively — no aarch64 RPM is ever produced whose single version string would
then name a payload it does not contain. Upstream must not copy this; see
[microshift-io/microshift#237](https://github.com/microshift-io/microshift/pull/237)
for the change that removes the need for the flag altogether.

**Unchanged input means no build.** A release branch build carries no timestamp
in its version, so the same commit built against the same payload produces an
identical NVR. The `setup` job queries the COPR API for a successful build
matching the branch tip and the resolved payload, and skips the build jobs when
it finds one. The `verify-repo` job still runs on those days: it checks the
published repository against the OpenShift mirror, which is exactly what is worth
knowing when nothing was rebuilt.

A `workflow_dispatch` run accepts `force: true` to build anyway.
