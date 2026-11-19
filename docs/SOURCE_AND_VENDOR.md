# Stream 2: Source Sync, Cryptographic Manifest Verification, `adevtool` Vendor Extraction, and Target Matrix

## Executive Summary & Architecture Overview

The build architecture of **GrapheneOS** (`https://grapheneos.org/build`) relies on an end-to-end cryptographic chain of trust and an automated vendor extraction pipeline (`adevtool`). For the `yubi-OS/grapheneOS` automation on our self-hosted `ubuntu` runner with storage mounted at `/mnt/extended`, Stream 2 establishes the fundamental supply-chain gate before any compilation occurs:
1. **Bootstrap & Cryptographic Manifest Verification**: The build machine bootstraps the standalone Google `repo` launcher under strict SHA-256 integrity verification, pins `REPO_REV` to prevent unreviewed runtime self-updates, validates the release manifest tag against the GrapheneOS SSH signing key via `allowed_signers`, and leverages the immutable property of commit-pinned manifests (`repo manifest -r`) to transitively verify all ~1,100+ sub-repositories.
2. **Throttled, Resumable Source Synchronization**: To operate safely on an I/O-sensitive, multi-tenant host with storage on `/mnt/extended`, `repo sync` must be throttled with `nice -n 19` and `ionice -c3`, constrained concurrency (`-j4`), and resilient error-handling flags (`--fail-fast`, `--force-sync`, `--no-clone-bundle`, `--no-tags`).
3. **`adevtool` Vendor Extraction Pipeline**: In GrapheneOS 17 (Android 17), proprietary hardware drivers, firmware, SELinux policies, VINTF entries, and carrier configs are generated directly from Google Pixel factory images and OTA packages via `vendor/adevtool`. Using Node.js 24 LTS and Yarn, `adevtool` downloads cryptographically verified stock OS images, unpacks partitions (including sparse and dynamic super images via `simg2img` and `lpunpack`), filters blobs against strict specification files (`vendor-specs/`), and generates complete Soong (`Android.bp`) and Make (`BoardConfigVendor.mk`, `device-vendor.mk`) module trees under `vendor/google_devices/<device>`.
4. **Target Matrix & Invocation Anatomy**: GrapheneOS defines emulator development targets (`sdk_phone64_x86_64` and `sdk_phone64_arm64`) built via default `m` invocations alongside production Pixel 6 through 10 generation targets. Because partition layouts evolved across device generations (specifically the introduction of vendor boot and vendor kernel boot partitions), `m` invocations differ significantly between Pixel 6 (`m vendorbootimage target-files-package`), Pixel 7–9 (`m vendorbootimage vendorkernelbootimage target-files-package`), and emulator / general targets.

---

## 1. `repo` Bootstrap & Cryptographic Verification Chain

### 1.1 Standalone `repo` Launcher Integrity
The Android Open Source Project (AOSP) distributes the standalone Python launcher script for `repo` via Google Cloud Storage. In contrast to distribution packages (e.g. `apt install repo`), which can lag significantly behind upstream Gerrit requirements or carry distribution-specific patches, GrapheneOS upstream supports both, but recommends the standalone self-updating launcher for automated production environments.

* **Download URL**: `https://storage.googleapis.com/git-repo-downloads/repo`
* **Pinned SHA-256 Digest**:
  ```
  05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a
  ```
* **Bootstrap Verification Snippet**:
  ```bash
  mkdir -p ~/.bin
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/.bin/repo
  echo "05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a  ${HOME}/.bin/repo" | sha256sum -c -
  chmod 755 ~/.bin/repo
  export PATH="${HOME}/.bin:${PATH}"
  ```

### 1.2 Upstream Gerrit Self-Update & GPG Verification Mechanism
When `repo init` is invoked, the launcher script does not execute the entire sync logic itself. Instead, it downloads the full `git-repo` tool from:
```
https://gerrit.googlesource.com/git-repo
```
into the workspace's `.repo/repo/` directory.

#### GPG Maintainer Keys Verification
The launcher script contains an embedded ASCII-armored keyring (`MAINTAINER_KEYS`, keyring version `2.3`). When downloading or updating the `git-repo` repository:
1. `repo` initializes an isolated GnuPG homedir inside `.repo/gnupg/`.
2. It imports the embedded `MAINTAINER_KEYS` into this temporary keyring.
3. It fetches the Git ref specified by `REPO_REV` (which defaults to the `stable` branch if unspecified).
4. It cryptographically verifies that the commit or tag at `REPO_REV` is signed by one of the authorized Google/AOSP maintainer keys before transferring execution control to `.repo/repo/main.py`.

#### The Supply-Chain Risk: `REPO_REV` Drift & Pinning
By default, `REPO_REV="stable"` tracks the moving `stable` branch on Gerrit. In a CI/CD automation pipeline (such as GitHub Actions running on our self-hosted runner), allowing `repo` to silently update itself introduces non-determinism, build breakages, and supply-chain exposure to unreviewed code.

To guarantee hermetic, reproducible builds, CI must explicitly pin `REPO_REV` to an immutable release tag (e.g. `v2.74`, commit `6405c052d61366d62fdc4a6dc318de3739f6dab9`, peeled commit `a816b88d2319089d5cbaa3fa336a68db917cb0f7`).
* **CI Pinning Contract in `PINNED.md`**:
  ```markdown
  | Component | Source URL | Pinned Ref / Tag | Digest / Commit SHA |
  |-----------|------------|------------------|---------------------|
  | repo launcher | https://storage.googleapis.com/git-repo-downloads/repo | - | `sha256:05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a` |
  | git-repo execution | https://gerrit.googlesource.com/git-repo | `refs/tags/v2.74` | `commit:6405c052d61366d62fdc4a6dc318de3739f6dab9` |
  ```
* **Invocation**:
  ```bash
  export REPO_REV="v2.74"
  # Or pass directly to repo init:
  repo init --repo-rev="v2.74" -u https://github.com/GrapheneOS/platform_manifest.git -b refs/tags/2026111800
  ```
This ensures `repo` verifies the GPG signature on tag `v2.74` and executes exactly the pinned version without polling or pulling newer code.

---

### 1.3 GrapheneOS SSH Tag Signature Verification & Allowed Signers
GrapheneOS signs all official Git release tags using OpenSSH digital signatures (introduced in OpenSSH 8.0+), providing a modern, collision-resistant alternative to PGP/GPG.

#### Allowed Signers Configuration
GrapheneOS publishes its official signing identity at:
```
https://grapheneos.org/allowed_signers
```
The canonical signer entry:
```
contact@grapheneos.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIUg/m5CoP83b0rfSCzYSVA4cw4ir49io5GPoxbgxdJE
```

#### Verification Command & Git Object Resolution
When initializing a build from a release tag (e.g. `2026111800`), the manifest repository (`.repo/manifests`) contains an annotated, signed tag. The verification sequence executes:
```bash
# 1. Download allowed_signers to a trusted path
curl -fsSL https://grapheneos.org/allowed_signers -o ~/.ssh/grapheneos_allowed_signers

# 2. Inside the manifest repo, configure git to use the allowedSignersFile
cd .repo/manifests
git config gpg.ssh.allowedSignersFile ~/.ssh/grapheneos_allowed_signers

# 3. Verify the annotated tag signature
git verify-tag $(git describe)
cd ../..
```

#### Cryptographic Anatomy of Tag `2026111800`
Taking the live production tag `2026111800` as a verified reference:
* **Tag Ref**: `refs/tags/2026111800`
* **Annotated Tag Object SHA**: `e5681d7438f52a75819d1f34f8d738fcaa54654c`
* **Peeled Commit Object SHA**: `c2f57432b89dda12ec40f07768d3c3a75bde9634`
* **Tagger**: `GrapheneOS <contact@grapheneos.org> 1795038729 -0500`
* **SSH Signature**:
  ```text
  -----BEGIN SSH SIGNATURE-----
  U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAghSD+bkKg/zdvSt9ILNhJUDhzDi
  Kvj2KjkY+jFuDF0kQAAAADZ2l0AAAAAAAAAAZzaGE1MTIAAABTAAAAC3NzaC1lZDI1NTE5
  AAAAQGXy02FoV1jiGP+/3fNJsjLOG8FFDdFhBKvYOsuiVqAmIzmGFdxCgByIMYrzXyBRLg
  icu+TPNJI9Ekh5GsidFgg=
  -----END SSH SIGNATURE-----
  ```
When `git verify-tag 2026111800` runs, Git extracts the tag payload, reconstructs the message, verifies the Ed25519 signature using the public key linked to `contact@grapheneos.org`, and validates that the tag points directly to commit `c2f57432b89dda12ec40f07768d3c3a75bde9634`.

---

### 1.4 Transitive Cryptographic Authentication of ~1,100+ Repositories
A critical security question in operating-system-scale source management: **How does verifying a single Git tag in `platform_manifest` guarantee the integrity of all ~1,100+ distinct repositories downloaded by `repo sync`?**

#### Manifest Modes: Branch Manifests vs Frozen Release Manifests
1. **Development Branches (e.g. `-b 17`)**: The manifest contains project entries specifying branch names (e.g. `revision="17"` or `revision="android-17.0.0_r1"`). In this mode, sub-repositories advance as new commits are pushed upstream; verifying the manifest tag does not freeze the sub-repositories unless each individual tag is audited.
2. **Frozen Stable Release Manifests (e.g. `-b refs/tags/2026111800`)**:
   GrapheneOS generates release manifests using `repo manifest -r` (or equivalent build release pipelines). In this manifest (e.g. `session/intake/grapheneos-2026111800-default.xml`), **every single sub-repository entry specifies an exact, immutable 40-character Git commit SHA-1/SHA-256 in its `revision` attribute**:
   ```xml
   <project name="platform/art" path="art" revision="e68fa7b22047ff0fce102f903e1e2c9ef895e632" upstream="refs/tags/2026111800" ... />
   <project name="adevtool" path="vendor/adevtool" remote="grapheneos" revision="b1c5b4411b7b46537c20f817c2ab68d49aa52820" ... />
   <project name="platform/bionic" path="bionic" revision="d3ac78f5664db696dbf5339f40774a814fe4c161" ... />
   ```

#### The Merkle Authentication Property
Because the manifest file (`default.xml`) is a physical file committed into the Git tree of commit `c2f57432b89dda12ec40f07768d3c3a75bde9634`, its contents form part of that commit's SHA-1/SHA-256 tree root.
* By verifying the cryptographic Ed25519 signature on tag `2026111800`, the signer (`contact@grapheneos.org`) signs the commit object.
* The commit object binds the exact bytes of `default.xml`.
* In Git, a commit object SHA is a cryptographic hash of its tree and commit metadata (including author, committer, and parent commits). It is cryptographically infeasible to alter any source file, commit message, or directory structure within any sub-project without changing that sub-project's commit SHA.
* Because `default.xml` pins the exact commit SHA for every one of the ~1,100+ repositories, verifying the single manifest tag transitively authenticates the entire source tree. No separate per-repository tag-verification script is needed or desired.

---

## 2. Throttled, Resumable `repo sync` on `ubuntu` (`/mnt/extended`)

### 2.1 Storage & Host Constraints on `ubuntu` Runner
The `ubuntu` self-hosted runner hosts CI builds on an extended storage volume at `/mnt/extended`. A standard AOSP + GrapheneOS source checkout requires **136 GiB+** of storage with commit history (or **90 GiB+** with shallow `--depth=1` sync), and the subsequent full OS build consumes an additional **100 GiB+** to **150 GiB+** per target architecture.

On a multi-tenant box where background services, monitoring bridges, and other builds may run concurrently, unthrottled `repo sync` can saturate both network bandwidth and disk I/O queues (leading to disk latency spikes, IOPS exhaustion, and socket timeouts).

### 2.2 Recommended Sync Invocation & Exact Flags
To ensure reliable, non-disruptive, and fully resumable downloads:

```bash
# 1. Directory creation on extended volume
mkdir -p /mnt/extended/grapheneos-2026111800
cd /mnt/extended/grapheneos-2026111800

# 2. Repo initialization targeting the verified tag
repo init -u https://github.com/GrapheneOS/platform_manifest.git \
          -b refs/tags/2026111800 \
          --repo-rev="v2.74"

# 3. Cryptographic tag verification of the manifest
(
  cd .repo/manifests
  git config gpg.ssh.allowedSignersFile ~/.ssh/grapheneos_allowed_signers
  git verify-tag 2026111800 || { echo "CRITICAL: Manifest tag signature verification failed!"; exit 1; }
)

# 4. Throttled, resilient synchronization
nice -n 19 ionice -c3 repo sync \
    -c \
    --no-clone-bundle \
    --no-tags \
    -j4 \
    --fail-fast
```

### 2.3 Detailed Flag Rationale & Failure Mode Analysis

| Flag | Technical Behavior | Operational Rationale |
|------|--------------------|-----------------------|
| `nice -n 19` | Lowest CPU scheduling priority | Prevents `repo sync` (and git pack-objects unpacking threads) from starving system processes or latency-critical daemons. |
| `ionice -c3` | Idle I/O scheduling class (CFQ/BFQ) | Forces disk writes/reads to yield whenever any normal process requests disk access on `/mnt/extended`. |
| `-c` (`--current-branch`) | Fetches only the currently checked-out commit/ref | Prevents fetching all remote branches across 1,100+ repos, saving tens of gigabytes of network transit and disk storage. |
| `--no-clone-bundle` | Bypasses CDN `clone.bundle` pre-packaged downloads | For Gerrit/GitHub mirrors, CDN clone bundles are frequently stale, missing for specific tags, or fail with HTTP 404/504 errors on automated runners. Direct Git fetch is more robust and prevents corrupt archive extraction. |
| `--no-tags` | Omits fetching Git tags in sub-repositories | Since the manifest pins exact commit SHAs (`revision="<SHA>"`), fetching thousands of unrelated upstream Git tags wastes significant metadata space and I/O cycles. |
| `-j4` | Restricts parallel network/git jobs to 4 | Default `repo sync` can launch 8–16+ parallel Git processes, saturating TCP connection pools and disk buffers. `-j4` maintains steady throughput without causing socket drops or thrashing. |
| `--fail-fast` | Aborts the sync immediately on the first network/git failure | Rather than spending 45 minutes continuing to sync 1,000 repositories when one critical repo has failed, CI fails early so network retries can be applied cleanly. |

### 2.4 Handling Interrupted Syncs & Fork Switching (`--force-sync`)

#### Resumability
`repo sync` is natively atomic and resumable at the repository level. Git fetches objects into `.repo/projects/<path>.git` or `.repo/project-objects/`. If a network disconnect or CI timeout occurs:
* Re-executing the identical `repo sync` command resumes fetching missing objects.
* Never run `rm -rf` on the workspace or `.repo` directory after an interrupted sync.

#### Switching Tags & The `--force-sync` Imperative
When updating between release tags or switching branches, GrapheneOS frequently introduces new custom forks of upstream AOSP projects (or removes existing forks and returns to AOSP upstream).
* **The Error**: When a repository's remote URL changes in the manifest (e.g. from `https://android.googlesource.com/...` to `https://github.com/GrapheneOS/...`), a standard `repo sync` will abort with an error indicating that the local checkout has diverged or points to a different remote.
* **The Resolution**:
  ```bash
  repo init -u https://github.com/GrapheneOS/platform_manifest.git -b refs/tags/<NEW_TAG>
  repo sync -c --no-clone-bundle --no-tags -j4 --force-sync
  ```
  `--force-sync` instructs `repo` to overwrite existing local tracking branches and re-point the working tree to the newly configured remote without requiring manual intervention.

---

## 3. `adevtool` Vendor Extraction Pipeline (`vendor/adevtool`)

### 3.1 Architectural Role of `adevtool` in GrapheneOS 17
AOSP source trees do not include proprietary vendor hardware drivers, modem firmware, GPU binaries, audio calibration tables, or carrier configurations necessary to run on physical Google Pixel devices. In legacy custom ROMs, developers relied on untracked binary blobs copied manually from running devices or extracted from outdated vendor zips.

GrapheneOS developed **`adevtool`** (`vendor/adevtool`, repository `https://github.com/GrapheneOS/adevtool`) to fully automate, standardize, and verify vendor support for all Google Pixel devices. In GrapheneOS 17 (Android 17):
* `adevtool` is a TypeScript application driven by the OCLif CLI framework.
* It executes under **Node.js 24 LTS** (required in `vendor/adevtool/bin/run`: `MIN_NODE_MAJOR_VERSION = 24`).
* It operates directly against official Google Pixel factory images and OTA packages.
* It parses, extracts, filters, and generates complete AOSP Soong build files (`Android.bp`) and Makefiles (`BoardConfigVendor.mk`, `device-vendor.mk`) under `vendor/google_devices/<device>`.

### 3.2 Setup & Dependencies
`adevtool` must be executed from the root of the GrapheneOS OS tree. It explicitly requires host prebuilts provided within the AOSP source tree (such as `prebuilts/build-tools/path/linux-x86` and `prebuilts/jdk/jdk21/linux-x86/bin`).

```bash
# Inside GrapheneOS source root:
cd vendor/adevtool
yarn install --frozen-lockfile
cd ../..

# Initialize AOSP build environment
source build/envsetup.sh
```

### 3.3 Factory Image Download & SHA-256 Digest Verification
`adevtool` maintains a cryptographic build index of all known Google Pixel factory images and full OTA zips:
* `vendor/adevtool/config/build-index/build-index-main.yml`
* `vendor/adevtool/config/build-index/build-index-canary.yml`
* `vendor/adevtool/config/build-index/build-index-beta.yml`

#### Pinned Digest Example (from `build-index-main.yml`):
```yaml
yogi CD1A.261005.003:
  desc: Oct 2026
  factory: 0f9fd538c4be6943421c85f55539000f519b1226db5e2ab9b95aa60d69759777 yogi-cd1a.261005.003-factory-0f9fd538.zip
  ota: fe783179759f1edd22eea66d1f63f98aec9837a3af0a89e01a3e178d3971b13f yogi-ota-cd1a.261005.003-fe783179.zip
```

#### Verification and Download Sequence
When `vendor/adevtool/bin/run generate-all -d <device>` (or `adevtool download -d <device>`) is invoked:
1. `adevtool` reads the device configuration (e.g. `config/device/<device>.yml`, including common fragments like `common/gen9pixel.yml` or `common/gen10pixel.yml`).
2. It resolves the pinned `build_id` for that device.
3. If the factory image zip is not present in the local download cache (configured via `IMAGE_DOWNLOAD_DIR`, defaulting to `~/.adevtool-cache/images` or workspace-relative cache), `adevtool` downloads the image from Google's official servers.
4. During download, it streams bytes into a temporary file (`.tmp`) and computes the SHA-256 digest on the fly via `hasha` / Node.js `crypto`.
5. If the computed digest does not match the pinned hash in `build-index-main.yml`, `adevtool` immediately throws an error and deletes the corrupted/tampered file.

---

### 3.4 Partition Unpacking & Toolchain
Once verified, `adevtool` unpacks the factory image archive:
1. **Archive Extraction**: The outer factory zip contains bootloader images, radio images, and a nested `image-<device>-<build_id>.zip`.
2. **Super Image Reconstruction & Splitting**:
   * Modern Pixels use dynamic partitions stored within `super.img`. In factory images, `super.img` is frequently split into sparse chunk images (`super_1.img`, `super_2.img`, etc.).
   * `adevtool` uses the host prebuilt tool `simg2img` (located via `getHostBinPath('simg2img')`) to un-sparse and concatenate the chunks into a unified raw `super.img`.
   * It then runs `lpunpack` (`getHostBinPath('lpunpack')`) on `super.img` to extract the constituent logical partitions:
     * `vendor.img`
     * `product.img`
     * `system_ext.img`
     * `system_dlkm.img` / `vendor_dlkm.img` / `odm_dlkm.img`
3. **Filesystem Traversal**:
   * `adevtool` extracts files from the ext4 / erofs partition images using prebuilt utilities (such as `debugfs` or native filesystem readers).
4. **Bootloader & Radio Firmware Extraction**:
   * Extracted from `bootloader.img` and `radio.img` using fastboot pack parsers (`src/images/fastboot-pack.ts` and `src/images/firmware.ts`).

---

### 3.5 Generation of `vendor/google_devices/<device>`
Following partition extraction, `adevtool` processes and filters the files through device-specific rules defined in `vendor/adevtool/config/device/`:
* **Module Generation**:
  * Shared libraries (`.so`) are converted into Soong `cc_prebuilt_library_shared` definitions with appropriate multilib and architecture targets (`android_arm`, `android_arm64`).
  * Proprietary APKs are converted into `android_app_import` modules, stripping Google certificates and configuring pre-opt settings.
  * Proprietary firmware files are staged into `vendor/google_devices/<device>/firmware/`.
* **Makefiles and Blueprint Files Created**:
  * `Android.bp`: Blueprint declarations for prebuilt libraries, binaries, HALs, and packages.
  * `BoardConfigVendor.mk`: Defines board-level vendor flags, partition sizes, SELinux policies, and AB OTA partition inclusions.
  * `device-vendor.mk`: Inherited by the main device product makefile, enumerating the packages and files copied into the target system image.
  * `adevtool-version-check.mk`: A defensive makefile assertion that verifies at build time that the checked-out commit of `vendor/adevtool` matches the exact revision used to generate the vendor tree:
    ```makefile
    ifneq ($(shell git -C vendor/adevtool rev-parse HEAD),b1c5b4411b7b46537c20f817c2ab68d49aa52820)
      $(error tokay vendor module is outdated. Run `adevtool generate-all -d tokay` to update it)
    endif
    ```

---

## 4. Build Targets & Variants Matrix

### 4.1 Target Classification: Emulator vs Physical Pixel Devices

GrapheneOS partitions its target matrix into two distinct categories:

| Target Category | Lunch Identifier | Intended Usage | Security Architecture & Update Posture |
|-----------------|------------------|----------------|-----------------------------------------|
| **SDK Emulator (x86_64)** | `sdk_phone64_x86_64-cur-userdebug` | Rapid CI functional validation, testing, automated unit tests | Runs inside QEMU/KVM; uses generic prebuilt kernels; **lacks** hardware MTE, Titan M2 security enclave, proprietary radio/camera HALs, and hardware verified boot. |
| **SDK Emulator (arm64)** | `sdk_phone64_arm64-cur-userdebug` | ARM64 virtualization testing | Runs on ARM64 runners (e.g. `rock1` / Apple Silicon KVM); shares emulator constraints. |
| **Production Pixels (6th–10th Gen)** | `<device>-cur-user` | Real device production releases | Full hardware verified boot (AVB), hardware memory tagging (MTE), Weaver/StrongBox attestation, complete monthly firmware updates. |

### 4.2 Comprehensive Device Matrix (Pixel 6 through 10)

| Codename | Commercial Name | Generation | SoC Platform | `m` Build Invocation |
|----------|-----------------|------------|--------------|------------------------|
| `oriole` | Pixel 6 | 6th Gen | Google Tensor (GS101) | `m vendorbootimage target-files-package` |
| `raven` | Pixel 6 Pro | 6th Gen | Google Tensor (GS101) | `m vendorbootimage target-files-package` |
| `bluejay` | Pixel 6a | 6th Gen | Google Tensor (GS101) | `m vendorbootimage target-files-package` |
| `panther` | Pixel 7 | 7th Gen | Tensor G2 (GS201) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `cheetah` | Pixel 7 Pro | 7th Gen | Tensor G2 (GS201) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `lynx` | Pixel 7a | 7th Gen | Tensor G2 (GS201) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `tangorpro`| Pixel Tablet | 7th Gen | Tensor G2 (GS201) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `felix` | Pixel Fold | 7th Gen | Tensor G2 (GS201) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `shiba` | Pixel 8 | 8th Gen | Tensor G3 (Zuma) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `husky` | Pixel 8 Pro | 8th Gen | Tensor G3 (Zuma) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `akita` | Pixel 8a | 8th Gen | Tensor G3 (Zuma) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `tokay` | Pixel 9 | 9th Gen | Tensor G4 (ZumaPro) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `caiman` | Pixel 9 Pro | 9th Gen | Tensor G4 (ZumaPro) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `komodo` | Pixel 9 Pro XL | 9th Gen | Tensor G4 (ZumaPro) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `comet` | Pixel 9 Pro Fold| 9th Gen | Tensor G4 (ZumaPro) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `tegu` | Pixel 9a | 9th Gen | Tensor G4 (ZumaPro) | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `frankel` | Pixel 10 | 10th Gen | Laguna Platform | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `blazer` | Pixel 10 Pro | 10th Gen | Laguna Platform | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `mustang` | Pixel 10 Pro XL | 10th Gen | Laguna Platform | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `rango` | Pixel 10 Pro Fold| 10th Gen | Laguna Platform | `m vendorbootimage vendorkernelbootimage target-files-package` |
| `stallion`| Pixel 10a | 10th Gen | Laguna Platform | `m vendorbootimage vendorkernelbootimage target-files-package` |

---

### 4.3 Deep Technical Dive: Why `m` Invocations Differ Across Generations

In upstream AOSP documentation for generic targets, the build command is simply:
```bash
m target-files-package
```
However, in GrapheneOS, building target-files packages for Pixel devices requires explicitly specifying additional image goals.

#### 1. Pixel 6 Series: `m vendorbootimage target-files-package`
* **Boot Architecture**: Introduced dedicated `vendor_boot` partition separate from the generic GKI `boot` partition. The `vendor_boot` image contains device-specific kernel modules, ramdisk, device-tree blobs (DTB), and boot parameters.
* **Build Dependency**: The target-files packaging step in Android's build system does not automatically resolve `vendor_boot.img` as an implicit prerequisite in certain Soong/Kati build graphs unless explicitly requested on the command line. Failing to pass `vendorbootimage` can result in an incomplete or stale `vendor_boot.img` being packaged into the target files archive.

#### 2. Pixel 7, 8, 9, and 10 Series: `m vendorbootimage vendorkernelbootimage target-files-package`
* **The Introduction of `vendor_kernel_boot`**:
  Starting with Android 13 and Pixel 7 (Tensor G2), Google separated the kernel ramdisk and vendor ramdisk further to support Generic Boot Image certification.
  * `boot.img`: Holds the generic upstream Linux GKI kernel binary.
  * `vendor_boot.img`: Holds SoC/board-specific boot configuration and vendor ramdisk.
  * `vendor_kernel_boot.img`: Holds vendor-specific kernel ramdisks (first-stage mount binaries, device tree fragments, early vendor modules needed before storage initialization).
* **The Target Dependency Hazard**:
  Building `target-files-package` alone evaluates the target files packaging rule, but `vendor_kernel_boot.img` is generated by a separate build rule (`vendorkernelbootimage`). Without explicitly listing both `vendorbootimage` and `vendorkernelbootimage` in the `m` invocation, the build system can complete `target-files-package` without generating the required boot image artifacts, causing fastboot flashing or release-signing scripts to fail.

#### 3. Emulator Builds: Faster Development Invocation
For emulator targets (`sdk_phone64_x86_64`):
```bash
source build/envsetup.sh
lunch sdk_phone64_x86_64-cur-userdebug
m -j$(nproc)
```
Because the emulator runs with an unlocked bootloader and public test keys, generating `target-files-package` and resigning with custom release keys is unnecessary. Running plain `m` builds raw system images in `out/target/product/emulator64_x86_64/`, which can be booted immediately via `emulator`.

---

## 5. Implementation Blueprint for `yubi-OS/grapheneOS` CI Workflow

### 5.1 CI Step Sequence on `ubuntu` Runner

```yaml
name: GrapheneOS Source & Adevtool Stage
on:
  workflow_dispatch:
    inputs:
      target_device:
        description: 'Target Device Codename (e.g. tokay, husky, sdk_phone64_x86_64)'
        required: true
        default: 'sdk_phone64_x86_64'
      manifest_tag:
        description: 'GrapheneOS Manifest Tag'
        required: true
        default: '2026111800'

jobs:
  sync_and_vendor:
    runs-on: [self-hosted, linux, ubuntu]
    steps:
      - name: Configure Storage Directory
        run: |
          mkdir -p /mnt/extended/grapheneos-ci
          echo "WORKSPACE_DIR=/mnt/extended/grapheneos-ci" >> $GITHUB_ENV

      - name: Bootstrap and Verify Repo
        run: |
          mkdir -p ~/.bin
          curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/.bin/repo
          echo "05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a  ${HOME}/.bin/repo" | sha256sum -c -
          chmod 755 ~/.bin/repo
          echo "${HOME}/.bin" >> $GITHUB_PATH

      - name: Initialize Repo with Pinned REPO_REV
        run: |
          cd $WORKSPACE_DIR
          export REPO_REV="v2.74"
          repo init -u https://github.com/GrapheneOS/platform_manifest.git \
                    -b refs/tags/${{ inputs.manifest_tag }} \
                    --repo-rev="v2.74"

      - name: Verify GrapheneOS Manifest Tag Signature
        run: |
          cd $WORKSPACE_DIR/.repo/manifests
          mkdir -p ~/.ssh
          curl -fsSL https://grapheneos.org/allowed_signers -o ~/.ssh/grapheneos_allowed_signers
          git config gpg.ssh.allowedSignersFile ~/.ssh/grapheneos_allowed_signers
          git verify-tag ${{ inputs.manifest_tag }}

      - name: Throttled Source Synchronization
        run: |
          cd $WORKSPACE_DIR
          nice -n 19 ionice -c3 repo sync -c --no-clone-bundle --no-tags -j4 --fail-fast

      - name: Extract Vendor Blobs via adevtool (Pixel targets only)
        if: ${{ inputs.target_device != 'sdk_phone64_x86_64' && inputs.target_device != 'sdk_phone64_arm64' }}
        run: |
          cd $WORKSPACE_DIR
          cd vendor/adevtool
          yarn install --frozen-lockfile
          cd ../..
          source build/envsetup.sh
          vendor/adevtool/bin/run generate-all -d ${{ inputs.target_device }}

      - name: Build Verification
        run: |
          cd $WORKSPACE_DIR
          source build/envsetup.sh
          if [ "${{ inputs.target_device }}" = "sdk_phone64_x86_64" ]; then
            lunch sdk_phone64_x86_64-cur-userdebug
            m -j4
          else
            lunch ${{ inputs.target_device }}-cur-user
            case "${{ inputs.target_device }}" in
              oriole|raven|bluejay)
                m -j4 vendorbootimage target-files-package
                ;;
              *)
                m -j4 vendorbootimage vendorkernelbootimage target-files-package
                ;;
            esac
          fi
```

---

## 6. References & Primary Sources

1. **GrapheneOS Official Build Documentation**: `https://grapheneos.org/build`
2. **GrapheneOS Allowed Signers**: `https://grapheneos.org/allowed_signers`
3. **GrapheneOS Platform Manifest Repository**: `https://github.com/GrapheneOS/platform_manifest`
   - Tag `2026111800` Tag Object: `e5681d7438f52a75819d1f34f8d738fcaa54654c`
   - Tag `2026111800` Commit: `c2f57432b89dda12ec40f07768d3c3a75bde9634`
4. **GrapheneOS `adevtool` Repository**: `https://github.com/GrapheneOS/adevtool`
   - Revision `b1c5b4411b7b46537c20f817c2ab68d49aa52820` (`refs/tags/2026111800`)
   - CLI Runner: `vendor/adevtool/bin/run`
   - Device configurations: `vendor/adevtool/config/device/`
   - Build indices: `vendor/adevtool/config/build-index/build-index-main.yml`
5. **Google Git Repo Source & Launcher**: `https://gerrit.googlesource.com/git-repo`
   - Standalone script: `https://storage.googleapis.com/git-repo-downloads/repo` (`sha256:05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a`)
   - Release ref: `refs/tags/v2.74`
6. **Local Intake Files**:
   - `session/intake/grapheneos-build.md`
   - `session/intake/grapheneos-2026111800-default.xml`
