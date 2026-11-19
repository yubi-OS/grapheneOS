# yubi-OS/grapheneOS

Reproducible, YubiKey-rooted **GrapheneOS 17** (`https://grapheneos.org/build`, tag `2026111800`) build and release pipeline running on the `yubi-OS` self-hosted `ubuntu` ARM64 HIGH-MEM runner with dedicated workspace storage on `/mnt/extended`.

> **Mission alignment:** Nothing in `yubi-OS/grapheneOS` asks you to trust an unverified binary or floating branch. Every manifest tag is verified with OpenSSH `allowed_signers`, every sub-repository is locked by commit SHA in [`PINNED.md`](PINNED.md), every downloaded tool is SHA-512 verified before execution, and release signing + hardware attestation bridge directly to the YubiKey root of trust (PIV `slot 9c` / FIDO2 `hmac-secret` + `Auditor`).

---

## Architecture & Prerequisite Documentation

| Document | Scope |
|----------|-------|
| [`PINNED.md`](PINNED.md) | Canonical pin table: GitHub Actions SHAs, SHA-256/SHA-512 direct downloads (`repo`, `allowed_signers`, Node.js 24 LTS, Android SDK, Gradle), GrapheneOS `2026111800` manifest & sub-project SHAs, kernel & Vanadium tags, and container digests. |
| [`docs/PREREQUISITES.md`](docs/PREREQUISITES.md) | **Stream 1:** Host OS & apt packages, `/mnt/extended` 285–440 GiB storage layout, ARM64 host vs `x86_64` AOSP prebuilt toolchain architecture (`qemu-user-static` `binfmt_misc` `flags: F` for Soong `nsjail` sandboxes + `setarch x86_64`), and `ubuntu` I/O throttling (`nice -n 19 ionice -c3`). |
| [`docs/SOURCE_AND_VENDOR.md`](docs/SOURCE_AND_VENDOR.md) | **Stream 2:** Standalone `repo` bootstrap (`REPO_REV=v2.74`), OpenSSH `allowed_signers` manifest signature verification, throttled resumable `repo sync`, `vendor/adevtool` Pixel factory image extraction, and the Pixel 6–10 + Emulator target matrix. |
| [`docs/PREBUILTS.md`](docs/PREBUILTS.md) | **Stream 3:** Out-of-tree prebuilt pipelines: GKI 6.18 & Microdroid 6.18 kernels, Pixel 6th–9th gen 6.1 Kleaf kernels, Pixel 10th gen 6.18 Laguna kernels, Vanadium 158 + `yubi-OS/chromium-provenance` (Antimony ADR-000) integration, and Standalone SDK / Gradle apps. |
| [`docs/SIGNING_AND_YUBIKEY.md`](docs/SIGNING_AND_YUBIKEY.md) | **Stream 4:** Complete `keys/<device>/` hierarchy (9 APK/APEX keys + AVB 2.0 4096-bit RSA + Ed25519 factory key), `/dev/shm` `tmpfs` + `swapoff -a` signing hygiene, mandatory `Updater` URL override (`https://ota.yubios.org/`), reproducible builds, and YubiKey PIV/FIDO2 signing & `Auditor` attestation. |
| [`refs/grapheneos-build-prerequisites-2026-11-19.md`](refs/grapheneos-build-prerequisites-2026-11-19.md) | Complete consolidated deep-research synthesis (mirrored in `yubi-OS/yubiOS/refs/grapheneos-build-prerequisites-2026-11-19.md`). |

---

## `/mnt/extended` Storage Layout on the `ubuntu` Runner

Root `/` on the `ubuntu` runner has ~67 GB free, whereas a GrapheneOS 17 checkout and build requires **~285 GiB** (lightweight `-c`) to **~440 GiB** (full history). All persistent build state lives under `/mnt/extended/grapheneos`, while decrypted signing keys live strictly in volatile `/dev/shm` `tmpfs`:

```text
/mnt/extended/grapheneos/
├── bin/               # SHA-512 verified standalone repo launcher & Node 24 LTS toolchain
├── .ssh/              # SHA-512 verified grapheneos_allowed_signers
├── manifest-check/    # Lightweight clone of GrapheneOS/platform_manifest for tag verification
├── workspace/         # Main GrapheneOS 17 repo checkout (.repo + 1,057 projects)
├── out/               # Soong/Ninja build output (OUT_DIR_COMMON_BASE)
├── ccache/            # Persistent compiler cache (CCACHE_DIR)
├── vendor_cache/      # Downloaded & SHA-256 verified Google Pixel factory images (adevtool)
├── kernels/           # Out-of-tree Kleaf kernel build workspaces (6.18 GKI, 6.1 Pixel, 6.18 Laguna)
├── vanadium/          # Out-of-tree Vanadium / Antimony-Android build workspace
├── sdk/               # Standalone Android SDK (cmdline-tools 11076708, build-tools 36.0.0, NDK 29)
└── releases/          # Signed factory images, full OTA zips, delta zips, and channel metadata
```

---

## Supported Build Targets

| Family | Codenames | `lunch` Target | Build Command (`m`) |
|--------|-----------|------------------|-----------------------|
| **SDK Emulator** | `sdk_phone64_x86_64`, `sdk_phone64_arm64` | `<target>-cur-userdebug` | `m -j8 -l10` |
| **Pixel 10th Gen (Laguna)** | `frankel` (10), `blazer` (10 Pro), `mustang` (10 Pro XL), `rango` (10 Pro Fold), `stallion` (10a) | `<device>-cur-user` | `m -j8 -l10 vendorbootimage vendorkernelbootimage target-files-package otatools-package` |
| **Pixel 9th Gen (ZumaPro)** | `tokay` (9), `caiman` (9 Pro), `komodo` (9 Pro XL), `comet` (9 Pro Fold), `tegu` (9a) | `<device>-cur-user` | `m -j8 -l10 vendorbootimage vendorkernelbootimage target-files-package otatools-package` |
| **Pixel 8th Gen (Zuma)** | `shiba` (8), `husky` (8 Pro), `akita` (8a) | `<device>-cur-user` | `m -j8 -l10 vendorbootimage vendorkernelbootimage target-files-package otatools-package` |
| **Pixel 7th Gen (GS201)** | `panther` (7), `cheetah` (7 Pro), `lynx` (7a), `tangorpro` (Tablet), `felix` (Fold) | `<device>-cur-user` | `m -j8 -l10 vendorbootimage vendorkernelbootimage target-files-package otatools-package` |
| **Pixel 6th Gen (GS101)** | `oriole` (6), `raven` (6 Pro), `bluejay` (6a) | `<device>-cur-user` | `m -j8 -l10 vendorbootimage target-files-package otatools-package` |

---

## GitHub Actions CI Pipeline (`.github/workflows/grapheneos-ci.yml`)

All builds execute via GitHub Actions on `runs-on: [self-hosted, Linux, ARM64, HIGH-MEM]` (`ubuntu`), enforcing:
1. **Host Load Gate**: Reads `uptime` and top CPU processes (`ps --sort=-pcpu`) before launching any heavy step.
2. **I/O Throttling**: Every sync and build command runs under `nice -n 19 ionice -c3` with bounded concurrency (`repo sync -j4`, `m -j8 -l10`).
3. **Stage Selection (`workflow_dispatch`)**:
   - `preflight-and-manifest` (default): Verifies host load, `/mnt/extended` free space, `PINNED.md` integrity, SHA-512 checksums of `repo` and `allowed_signers`, clones `GrapheneOS/platform_manifest` at tag `2026111800`, cryptographically verifies the OpenSSH Ed25519 signature + peeled commit `c2f57432b89dda12ec40f07768d3c3a75bde9634`, audits host packages and `binfmt_misc`, and validates `scripts/patch-updater-url.sh` and `scripts/yubikey-avb-signer.sh`.
   - `sync`: Initializes and runs throttled `repo sync -c --no-clone-bundle --no-tags -j4 --fail-fast` into `/mnt/extended/grapheneos/workspace`.
   - `adevtool`: Bootstraps pinned Node.js `v24.22.3` + Corepack Yarn and runs `vendor/adevtool/bin/run generate-all -d <target>` with `ADEVTOOL_CACHE_DIR=/mnt/extended/grapheneos/vendor_cache`.
   - `prebuilts`: Builds out-of-tree kernel/Vanadium/standalone app prebuilts on `/mnt/extended/grapheneos/`.
   - `build`: Applies `scripts/patch-updater-url.sh`, enters `setarch x86_64` (with `qemu-x86_64-static` `flags: F`), runs `source build/envsetup.sh && lunch <target>-cur-<variant>`, and executes the throttled `m` build with `OUT_DIR_COMMON_BASE=/mnt/extended/grapheneos/out`.
   - `release-sign`: Verifies `swapoff -a`, unseals keys into `/dev/shm` `tmpfs` (or invokes `scripts/yubikey-avb-signer.sh`), runs `script/finalize.sh` and `script/generate-release.sh`, and scrubs `/dev/shm` on exit.
