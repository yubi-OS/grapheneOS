# PINNED.md - yubi-OS/grapheneOS approved refs & digests

_Last reviewed: 2026-11-19 during initial `yubi-OS/grapheneOS` repository setup and GrapheneOS 17 (`2026111800`) CI pipeline creation._

All GitHub Actions, direct workflow downloads, upstream GrapheneOS and AOSP source refs, kernel/browser prebuilt refs, and container image references used in `yubi-OS/grapheneOS` must appear here before being added to any workflow or script. Non-pinned refs such as mutable tags and branch names are not permitted.

**This file is the single source of truth.** Workflows and build scripts consume the immutable digests and commit hashes recorded below, with an inline comment next to each pinned digest carrying its version number or tag.

---

## GitHub Actions

| Action | Pinned SHA |
|--------|------------|
| `0mniteck/.pki` | `*` (org-internal workflows only, ref matches `.github/*/*@*`) |
| `actions/attest` | `1e69f48acb82d1966a394da916b4c1698aa569d6` `# v4.2.2` |
| `actions/checkout` | `3d3c42e5aac5ba805825da76410c181273ba90b1` `# v7.0.1` |
| `actions/download-artifact` | `9000827ccba6bdab643e8b6fd33ac0654aef8333` `# v8.0.2` |
| `actions/setup-python` | `6d4fd22b20465ccc0f7354476588e8df7c9ca0e0` `# v7.1.0` |
| `actions/upload-artifact` | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` `# v7.0.2` |
| `docker/setup-buildx-action` | `f87e5991a6d7451dcb8d9637bfbc97413f497069` `# v4.4.1` |

## Direct Workflow Downloads

Every downloaded workflow artifact is verified with both `sha256sum --check --strict` and `sha512sum --check --strict` before it is extracted, installed, or executed.

| Artifact URL | Platform | Pinned SHA-256 | Pinned SHA-512 |
|--------------|----------|----------------|----------------|
| `https://storage.googleapis.com/git-repo-downloads/repo` | `any` | `05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a` `# repo-launcher-2.74` | `710d15d09903655d4df5b4f2562f0a1257dd5e0da3ed723e92853b8fe4228a1aaccf978d7044c56f23e40db9ba26ec1460072f41062aa31b0e713d31e586970b` `# repo-launcher-2.74` |
| `https://grapheneos.org/allowed_signers` | `any` | `344f59c6f058699e63fea68e35953b341c14e3bf1fbc1256f6baa84aa2aca1d0` `# contact@grapheneos.org` | `af6ae0ca380a83da7b3e3cca0aa4d28f91554628610c869fa159f6ea5c4cda07138c4c621117088a63463d0cec20196ff81a08a7d6d16c19402b5c1fd3cff590` `# contact@grapheneos.org` |
| `https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip` | `linux/amd64` | `2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258` `# 11076708` | `d143221d0957256c5b172a5be70e5f098a08b2b3097a20c576c8febf444a00a64f626a7f651a7d5123b9ba32418dc0ae7053d0b4b52c40f772a6a1fb19a95417` `# 11076708` |
| `https://nodejs.org/dist/v24.22.3/node-v24.22.3-linux-arm64.tar.xz` | `linux/arm64` | `6e51a2ada00f0011cc266f65d98922b403d7ad88f809ca2aa615a5fe1ce6e86c` `# v24.22.3` | `69acc8f30bb09dcc2882ea495bc1b01f74471b17d3aebbe796fa583618c89fb193218e6f7b07123ef60a9308a64c0963641fb85636b2235e1b8dae2b9d3c3ac8` `# v24.22.3` |
| `https://nodejs.org/dist/v24.22.3/node-v24.22.3-linux-x64.tar.xz` | `linux/amd64` | `4f2b175a6d53a5c617a80dba2676238a0688cef28c6da4eba35c7d844e66fcfb` `# v24.22.3` | `110d7ab36900d3cc9069e36880374de419654a878dd09c1e48cbfd8907eed56f242c546eb49b972179081e230cbe1b0d30b7d27360e1df8a79f2f8e8753b8303` `# v24.22.3` |
| `https://services.gradle.org/distributions/gradle-8.10.2-bin.zip` | `any` | `31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26` `# 8.10.2` | `c48d4b7f4a7b6aa4886848ce913b099b8b7f2494b3d0ca86a21588f6482a185265fffeb0bb6da5f52b8c5f958e589d3a8be9c7fd846790ffbe12be1ad05c9f4f` `# 8.10.2` |
| `https://download.docker.com/linux/static/stable/aarch64/docker-29.9.3.tgz` | `linux/arm64` | `-` | `373b7542d225479e066cb540889cf24035f7909a17519845bedb93bb0b208c3bdd778af47d412de52136bf98d63ac1a5aba76e09eacd15641151c6e7f73aa198` `# 29.9.3` |
| `https://download.docker.com/linux/static/stable/aarch64/docker-rootless-extras-29.9.3.tgz` | `linux/arm64` | `-` | `7bab17249d06874cd5900ffc9908db692e8f158e17b03fc8afff5b9feaab5044752f7a018225695f8ca548212fa4d5095c3f15d0b06ed263f00ab4a895d6fc8a` `# 29.9.3` |
| `https://github.com/docker/buildx/releases/download/v0.39.0/buildx-v0.39.0.linux-arm64` | `linux/arm64` | `-` | `810c87058af0abb1205366d85ac47c3b1111676f7ae411fba19d3fe49a13a0695fe0d8bb03cdbd097132507eec19c7aecf4189e3ca30cab0e4a2a3b92ce8ad2b` `# v0.39.0` |
| `https://github.com/sigstore/cosign/releases/download/v3.1.4/cosign-linux-arm64` | `linux/arm64` | `ade83b7aac62e131cacfe96d958948b2150cc9efec46a570a2649b8e27dedad2` `# v3.1.4` | `dcf1a8745b03c9c7cf915ebeb34f287a5ade8bd975699ff7c221440ce8fabbacec98cc1a1728444c80d63c3372029d33973863ca07b2634e4c196e178a2d7f86` `# v3.1.4` |

| `https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-linux-arm64-v3.7.1.tar.gz` | `linux/arm64` | `73a9c90eeb4312133a63c3eaee0c38c019ea7bfa0953d174809d25b18588dd8d` `# v3.7.1` | `858ff2c5bec3b278acba3b6fe19b229d7786c723b177408a111953c367c2f93693108bdd445aa6702d88e31ad857adf91284afb75ed5be5bec1a23472d19de55` `# v3.7.1` |
| `https://dl.google.com/dl/android/aosp/stallion-cp4a.261105.040.a1-factory-45cdadb1.zip` | `stallion (Pixel 10a)` | `45cdadb1e34b4dd4462069a36c131ebe3a05d9d4be5f567f9cd61b7c69d5dbe8` `# CP4A.261105.040.A1` | `verified by adevtool build-index-main.yml` `# CP4A.261105.040.A1` |
| `https://dl.google.com/dl/android/aosp/stallion-ota-cp4a.261105.040.a1-91604ff1.zip` | `stallion (Pixel 10a)` | `91604ff11cdc0f909e32c369cbd4448ce00d5b0a7fbc17859e6a779ab2808693` `# CP4A.261105.040.A1` | `verified by adevtool build-index-main.yml` `# CP4A.261105.040.A1` |

## GrapheneOS & AOSP Source Refs

Workflows verify the annotated SSH-signed tag `2026111800` (`e5681d7438f52a75819d1f34f8d738fcaa54654c`) against `allowed_signers` and assert that the peeled manifest commit is `c2f57432b89dda12ec40f07768d3c3a75bde9634`. Because the `2026111800` release manifest pins all 1,057 projects (148 GrapheneOS forks + 909 AOSP projects) by exact 40-character commit SHA, verifying the manifest tag transitively authenticates the entire OS tree.

| Repository / Project Path | Upstream Remote | Reviewed Tag / Branch | Pinned Commit SHA | Role |
|---------------------------|-----------------|-----------------------|-------------------|------|
| `GrapheneOS/platform_manifest` (tag object) | `github.com/GrapheneOS` | `refs/tags/2026111800` | `e5681d7438f52a75819d1f34f8d738fcaa54654c` `# 2026111800 (tag)` | Annotated SSH-signed release tag object (`contact@grapheneos.org`). |
| `GrapheneOS/platform_manifest` (commit) | `github.com/GrapheneOS` | `refs/tags/2026111800` | `c2f57432b89dda12ec40f07768d3c3a75bde9634` `# 2026111800` | Peeled manifest commit locking all 1,057 sub-projects by commit SHA. |
| `GrapheneOS/platform_manifest` (dev head) | `github.com/GrapheneOS` | `17` | `5aa920927a5fdec242a65ccc3958100a14ec8959` `# 17` | GrapheneOS Android 17 development branch reference. |
| `gerrit.googlesource.com/git-repo` | `googlesource` | `v2.74` | `6405c052d61366d62fdc4a6dc318de3739f6dab9` `# v2.74` | Pinned `--repo-rev` passed to `repo init` to prevent unreviewed self-updates. |
| `script` (`GrapheneOS/script`) | `github.com/GrapheneOS` | `2026111800` | `01b6eac9fa9287ee76b973362b47e661902d0299` `# 2026111800` | Release finalization, key encryption/decryption (`tmpfs`), OTA & delta generation. |
| `vendor/adevtool` (`GrapheneOS/adevtool`) | `github.com/GrapheneOS` | `2026111800` | `b1c5b4411b7b46537c20f817c2ab68d49aa52820` `# 2026111800` | Pixel factory image SHA-256 verifier, partition extractor, and vendor module generator. |
| `external/vanadium` (`platform_external_vanadium`) | `gitlab.com/grapheneos` | `2026111800` | `17a788f57d9d9031031084bea9d5d54f9dc28f30` `# 2026111800` | Prebuilt Vanadium Browser, System WebView, TrichromeLibrary, and VanadiumConfig APKs. |
| `GrapheneOS/Vanadium` (source build repo) | `github.com/GrapheneOS` | `158.0.8127.42.0` | `e017f70b2fbb4bfaef81a6b1c49ac51ff886aca2` `# 158.0.8127.42.0` | Out-of-tree Chromium 158 hardening patches and `args.gn` for Vanadium. |
| `yubi-OS/chromium-provenance` | `github.com/yubi-OS` | `antimony-v156.0.8078.47-r1` | `c2789f3690f158585852f2950e682a45ca3c3c9f` `# antimony-v156.0.8078.47-r1` | Antimony ADR-000 fail-closed provenance-gate patch series for WebView/Browser integration. |
| `external/hardened_malloc` | `github.com/GrapheneOS` | `2026111800` | `c5b1ae0bacd896bff7c4d3bf4794adf7950ca4ab` `# 2026111800` | GrapheneOS security-hardened memory allocator integrated into Bionic. |
| `packages/apps/Updater` | `github.com/GrapheneOS` | `2026111800` | `bfe6ad3f57b7bc4271244b2ab6069698b5975748` `# 2026111800` | OS OTA update client (`res/values/config.xml` URL overridden to `https://ota.yubios.org/`). |
| `external/Auditor` | `github.com/GrapheneOS` | `2026111800` | `8115eb9d03e8b77dd54f5931d50aacc6b19a04fb` `# 2026111800` | Hardware-backed attestation app (paired with custom `avb_pkmd.bin` SHA-256 fingerprint). |
| `external/AppStore` | `github.com/GrapheneOS` | `2026111800` | `57a8107a4aba6774c2215fb454772b1a20b7f346` `# 2026111800` | GrapheneOS standalone App Store client prebuilt. |
| `external/Camera` | `github.com/GrapheneOS` | `2026111800` | `1e8ea44155ce3c023d9b1486d57a44268276c315` `# 2026111800` | GrapheneOS privacy-hardened Camera app prebuilt. |
| `external/PdfViewer` | `github.com/GrapheneOS` | `2026111800` | `20956d0128962a35414280b1a7dc4ab6527f2e4d` `# 2026111800` | GrapheneOS sandboxed PDF Viewer app prebuilt. |
| `external/GmsCompatConfig` | `github.com/GrapheneOS` | `2026111800` | `fc0f96a916f59759c645f219b4f867b9c5e91fed` `# 2026111800` | Sandboxed Google Play compatibility configuration prebuilt. |
| `external/AppCompatConfig` | `github.com/GrapheneOS` | `2026111800` | `8798038537b1951d626e8ce8204269c3abacf376` `# 2026111800` | Per-package exploit mitigation compatibility configuration prebuilt. |
| `external/talkback` | `github.com/GrapheneOS` | `2026111800` | `cd7e4aafe2e228fd3767129623cd0d1dda7384d0` `# 2026111800` | GrapheneOS TalkBack screen reader fork. |
| `build/make` (`platform_build`) | `github.com/GrapheneOS` | `2026111800` | `3ec7131c58881d0b5e751775cf76986fe3889517` `# 2026111800` | Core AOSP/GrapheneOS Make & `releasetools` build system. |
| `build/soong` (`platform_build_soong`) | `github.com/GrapheneOS` | `2026111800` | `250710f7f87acfbb8e3c517d90abde8b4a08fe1e` `# 2026111800` | Soong blueprint build system and `nsjail` sandbox runner. |
| `build/release` (`platform_build_release`) | `github.com/GrapheneOS` | `2026111800` | `ae3ffb8d0642486c4fa67d6ee3d93624de692373` `# 2026111800` | Release flag configurations (`cur` release config). |
| `bionic` (`platform_bionic`) | `github.com/GrapheneOS` | `2026111800` | `e93ce48518dc0fba69878cb4ace37a3525862cbe` `# 2026111800` | Hardened C library, dynamic linker, and MTE integration. |
| `art` (`platform_art`) | `github.com/GrapheneOS` | `2026111800` | `6a459adafb78451393b2bfb45e805934df2a3d6b` `# 2026111800` | Hardened Android Runtime (ART). |
| `frameworks/base` (`platform_frameworks_base`) | `github.com/GrapheneOS` | `2026111800` | `f7be495a0f1f4b9a1bd9f2238441f81371624b82` `# 2026111800` | Core Android framework, network/sensor permission toggles, WebView provider whitelist. |
| `system/sepolicy` (`platform_system_sepolicy`) | `github.com/GrapheneOS` | `2026111800` | `e9cc3685467b6daffd331461c94a3b848164930a` `# 2026111800` | Hardened SELinux policy domains and neverallow rules. |

## Kernel Manifests & Prebuilt Kernel Refs

| Repository / Project Path | Upstream Remote | Reviewed Tag / Branch | Pinned Commit SHA | Target Devices |
|---------------------------|-----------------|-----------------------|-------------------|----------------|
| `GrapheneOS/kernel_manifest-6.18` | `github.com/GrapheneOS` | `17` | `fae63ef0c2a745e2d7b798f76e3269e9859e0366` `# 17` | Generic 6.18 GKI (Emulator/Cuttlefish) & Microdroid 6.18 kernel manifest. |
| `gitlab.com/grapheneos/kernel_pixel_6.1` | `gitlab.com/grapheneos` | `17-qpr2` | `ad2669e3d58d23f5cd2f92fba95fd0701ef7e117` `# 17-qpr2` | Pixel 6th–9th Gen 6.1 kernel source tree (`raviole`, `bluejay`, `pantah`, `lynx`, `tangorpro`, `felix`, `shusky`, `akita`, `caimito`, `comet`, `tegu`). |
| `gitlab.com/grapheneos/kernel_pixel_6.1` (stallion) | `gitlab.com/grapheneos` | `17-qpr2-stallion` | `7f2c1461be5c853384f798eed7ac35ed47b7c6af` `# 17-qpr2-stallion` | Pixel 10a (`stallion`) kernel source tree. |
| `GrapheneOS/kernel_pixel` (10th gen muzel) | `github.com/GrapheneOS` | `17-qpr2-muzel` | `17d0abda61edb30a258fdd70e4ae47f8c709fd82` `# 17-qpr2-muzel` | Pixel 10th Gen (`frankel`, `blazer`, `mustang`, `rango`) 6.18 Laguna kernel source tree. |
| `device/google/laguna-kernels/6.18` | `github.com/GrapheneOS` | `2026111800` | `332187071514f62fed5f56e0b6b3fa2fdc196629` `# 2026111800` | Prebuilt 6.18 kernels for Pixel 10 series (`muzel`, `rango`). |
| `device/google/pixel-kernels/6.18` | `github.com/GrapheneOS` | `2026111800` | `46ce02b1cbd27e10e7965aba63e078cb45f6f315` `# 2026111800` | Prebuilt 6.18 kernels for pre-Laguna Pixels. |
| `device/google/caimito-kernels/6.1` | `github.com/GrapheneOS` | `2026111800` | `4b9d79b31f4fe9586d80c9e64399a06347a1d037` `# 2026111800` | Prebuilt 6.1 kernels for Pixel 9 / 9 Pro / 9 Pro XL (`tokay`, `caiman`, `komodo`). |
| `device/google/comet-kernels/6.1` | `github.com/GrapheneOS` | `2026111800` | `59bac0f19571ee1faff83f4cb2f1a591f4ec38ca` `# 2026111800` | Prebuilt 6.1 kernels for Pixel 9 Pro Fold (`comet`). |
| `device/google/tegu-kernels/6.1` | `github.com/GrapheneOS` | `2026111800` | `13101d16a4a6b5062b17151f8ed875fbdcbf23bb` `# 2026111800` | Prebuilt 6.1 kernels for Pixel 9a (`tegu`). |
| `device/google/shusky-kernels/6.1` | `github.com/GrapheneOS` | `2026111800` | `bef9cd99efe662b160ba5423c60b4aa4e8ee2c07` `# 2026111800` | Prebuilt 6.1 kernels for Pixel 8 / 8 Pro (`shiba`, `husky`). |
| `device/google/akita-kernels/6.1` | `github.com/GrapheneOS` | `2026111800` | `52af5ac7e1c6fe6015c1e03669e07dac5fe62229` `# 2026111800` | Prebuilt 6.1 kernels for Pixel 8a (`akita`). |
| `device/google/stallion-kernels/6.1` | `github.com/GrapheneOS` | `2026111800` | `edd2fa462c41f335ad4c5e65b024fba2a276d0d9` `# 2026111800` | Prebuilt 6.1 kernels for Pixel 10a (`stallion`). |
| `kernel/prebuilts/6.18/arm64` | `github.com/GrapheneOS` | `2026111800` | `c01961a7478844c1a12f8b86afb3791225b04312` `# 2026111800` | Generic 6.18 ARM64 kernel prebuilt. |
| `kernel/prebuilts/6.18/x86_64` | `github.com/GrapheneOS` | `2026111800` | `c17102894e49681570cf278837ed3cbc236f0ac9` `# 2026111800` | Generic 6.18 x86_64 kernel prebuilt. |

## Container Images

| Image | Pinned Digest | Notes |
|-------|---------------|-------|
| `dhi.io/debian-base` (multi-arch INDEX) | `sha256:f90fd43cdf3dd94840b4dc3a2a39fd2a08578e40e7895535e2e20a1275ba6013` `# trixie-debian13-dev` | Canonical org-wide base container index. |
| `dhi.io/debian-base` (`linux/amd64` child) | `sha256:d04db6fb809bc4f8eff61a7af5bed61a3f64a1205804700648b00582d75fbfb2` `# trixie-debian13-dev (linux/amd64)` | Used when running an isolated `linux/amd64` sysroot/container for AOSP `linux-x86` prebuilts on the ARM64 `ubuntu` host. |
| `dhi.io/debian-base` (`linux/arm64` child) | `sha256:2ad1aef2fbf08d841bbf55e0e583c445511d0eb1e130bc7389911cd1627b1ce4` `# trixie-debian13-dev (linux/arm64)` | Native ARM64 child digest. |
| `docker.io/moby/buildkit:v0.35.0` (multi-arch INDEX) | `sha256:aa632b921ef07411d2cb77292cd34213d4f7b384001d6fceef1e1f25bf9752bb` `# v0.35.0` | BuildKit daemon for rootless container builds (ADR-014). |
| `ghcr.io/hadolint/hadolint:v2.15.1-debian` | `sha256:9a3944b7fddcb947d1ffd90829ac1a6e5c30479223358f249d8b96c7d0019e27` `# v2.15.1-debian` | Containerfile linter image index. |

---

## Policy

- All GitHub Actions `uses:` entries, container image references, direct workflow downloads, and upstream GrapheneOS/AOSP manifest revisions must match an entry pinned in this file, with an inline version comment next to each digest.
- Every downloaded binary or script (`repo`, `allowed_signers`, `node`, `commandlinetools`, `gradle`, `cosign`) must pass `sha256sum --check --strict` and `sha512sum --check --strict` before execution.
- Manifest checkout must verify the OpenSSH Ed25519 tag signature against `allowed_signers` (`git verify-tag`) and confirm that the peeled commit SHA matches the pinned commit in the table above before running `repo sync`.
