# Versioning Scheme

Upstream packages are based on MicroShift code and OKD images.
To allow for easy identification and tracking of what is included in the package,
following versioning scheme is used: `MICROSHIFT-VERSION`_g`MICROSHIFT-GIT-COMMIT`_`OKD-VERSION`:

- `MICROSHIFT-VERSION` can have three forms:
  - `X.Y.Z-YYYYMMDDHHMM.pN` or `X.Y.Z-{e,r}c.M-YYYYMMDDHHMM.pN` if it is based on [openshift/microshift tags](https://github.com/openshift/microshift/tags).
  - `X.Y.Z-N` if it was built against a release branch, where `X.Y.Z` is the
    nearest release tag reachable from the branch tip and `N` the number of
    commits since it. `Makefile.version.*.var` cannot be used here: it stores the
    OCP base version, which is always `X.Y.0`, so every 4.22 build would claim to
    be `4.22.0` no matter how far the branch has moved past `4.22.7`.
  - `X.Y.Z` if it was built against a branch with no release tag of its own stream
    in its history (e.g. `main`), value of `X.Y.Z` is based on version stored in
    `Makefile.version.*.var` file, followed by a build timestamp.
- `MICROSHIFT-GIT-COMMIT` is the [openshift/microshift](https://github.com/openshift/microshift) commit.
- `OKD-VERSION` is a tag of the OKD release image from which the component image references are sourced.

Examples:
- `4.22.7_29_gef322212c_4.22.0_okd_scos.9`
  - `29` after the `X.Y.Z` means it was built from a release branch whose tip is
    29 commits past [MicroShift release tag 4.22.7](https://github.com/openshift/microshift/releases/tag/4.22.7-202607240848.p0)
  - Component image references are sourced from [4.22.0-okd-scos.9 release](https://github.com/okd-project/okd/releases/tag/4.22.0-okd-scos.9)
- `4.21.0_ga9cd00b34_4.21.0_okd_scos.ec.5`
  - Missing `YYYYMMDDHHMM.pN` means it was built against a branch, not a tag (release)
  - `4.21.0` means that commit [a9cd00b34](https://github.com/openshift/microshift/commit/a9cd00b341191e2091937a1f982168964c105297) was part of 4.21 release (but it could be built from main)
  - Component image references are sourced from [4.21.0-okd-scos.ec.5 release](https://github.com/okd-project/okd/releases/tag/4.21.0-okd-scos.ec.5)
- `4.20.0-202510201126.p0-g1c4675ace_4.20.0-okd-scos.6`
  - `202510201126.p0` is present which means it was built from [MicroShift release tag 4.20.0-202510201126.p0](https://github.com/openshift/microshift/releases/tag/4.20.0-202510201126.p0)
  - MicroShift tag points to [1c4675ace](https://github.com/openshift/microshift/commit/1c4675ace39e1ef9c4919218c15d21e8793f6254) commit.
  - Component image references are sourced from [4.20.0-okd-scos.6 release](https://github.com/okd-project/okd/releases/tag/4.20.0-okd-scos.6)
