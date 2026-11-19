# Stream 3: Prebuilt Code Pipelines (Kernels, Microdroid, Vanadium/Antimony, and Standalone Apps)

**Date**: November 19, 2026  
**Context**: `yubi-OS/grapheneOS` Build Infrastructure & CI Architecture  
**Target Runner**: `ubuntu` Self-Hosted HIGH-MEM Runner (`/mnt/extended`, 647 GB available ext4 on LUKS)  
**Upstream Reference**: [GrapheneOS Build Documentation](https://grapheneos.org/build#prebuilt-code)

---

## 1. Executive Summary & Architectural Positioning

Like upstream Android Open Source Project (AOSP), GrapheneOS encapsulates certain high-complexity, standalone components as **prebuilt binaries** bundled into the operating system source tree. Building these components out-of-tree guarantees reproducible toolchains, separates monolithic OS build cycles from upstream component update cadences, and isolates distinct build technologies:
- **Kleaf / Bazel hermetic kernel toolchains** for Linux kernels (GKI 6.18, Microdroid 6.18, Tensor G1–G4 6.1, Tensor G5 6.18).
- **Chromium / GN / Ninja (`autoninja`) toolchains** for Vanadium WebView, Vanadium Browser, and VanadiumConfig APKs.
- **Gradle & Android Standalone SDK toolchains** for standalone security and system APKs (`AppStore`, `Auditor`, `Camera`, `PdfViewer`, `AppCompatConfig`, `GmsCompatConfig`, `TalkBack`).

This document provides the definitive implementation blueprint for **Stream 3 CI pipelines**, detailing repository topologies, execution workflows, output destination paths within `grapheneos-17`, artifact signing protocols, and strategic synergies with `yubi-OS/chromium-provenance` (Antimony).

---

## 2. Kernel Build Pipelines

GrapheneOS isolates the Linux kernel from the Android platform build system. Kernels compile using hermetic toolchains pinned within kernel manifests or submodules, preventing contamination from host OS compiler versions.

```
                    ┌───────────────────────────────────────────┐
                    │       GrapheneOS Kernel Pipelines         │
                    └─────────────────────┬─────────────────────┘
                                          │
       ┌───────────────────┬──────────────┴──────┬───────────────────┐
       ▼                   ▼                     ▼                   ▼
┌──────────────┐   ┌──────────────┐      ┌──────────────┐    ┌──────────────┐
│ Emulator/CF  │   │  Microdroid  │      │ Pixel 6th–9th│    │  Pixel 10th  │
│ GKI 6.18     │   │     6.18     │      │   6.1 LTS    │    │   6.18 LTS   │
├──────────────┤   ├──────────────┤      ├──────────────┤    ├──────────────┤
│build_generic │   │Bazel target: │      │Kleaf/Bazel:  │    │Sync script:  │
│.sh           │   │//common:     │      │build_<code-  │    │./build_<cd>- │
│(aarch64/x86) │   │kernel_*_dist │      │name>.sh      │    │name>.sh      │
└──────┬───────┘   └──────┬───────┘      └──────┬───────┘    └──────┬───────┘
       │                  │                     │                   │
       ▼                  ▼                     ▼                   ▼
┌──────────────┐   ┌──────────────┐      ┌──────────────┐    ┌──────────────┐
│device/google/│   │packages/     │      │device/google/│    │device/google/│
│cuttlefish_   │   │modules/      │      │<device>-     │    │laguna-       │
│prebuilts/    │   │Virtualization│      │kernels/6.1/  │    │kernels/6.18/ │
│kernel/6.18/  │   │/microdroid/  │      │grapheneos/   │    │grapheneos/<cd│
└──────────────┘   └──────────────┘      └──────────────┘    └──────────────┘
```

---

### 2.1 Emulator & Cuttlefish 6.18 (GKI)

- **Source Manifest Repository**: `https://github.com/GrapheneOS/kernel_manifest-6.18.git`
- **Branch**: `17`
- **Target Architectures**: `aarch64` (`arm64`), `x86_64`

#### Pipeline Workflow
1. **Workspace Initialization**:
   ```bash
   mkdir -p /mnt/extended/kernel/6.18
   cd /mnt/extended/kernel/6.18
   repo init -u https://github.com/GrapheneOS/kernel_manifest-6.18.git -b 17 --depth=1
   repo sync -c -j$(nproc)
   ```
2. **Build Generic Images & Modules**:
   - ARM64:
     ```bash
     ARCH=aarch64 common/build_generic.sh
     ```
   - x86_64:
     ```bash
     ARCH=x86_64 common/build_generic.sh
     ```
3. **Prebuilt Tree Integration**:
   Artifacts are deployed into the platform tree using the upstream update helper script:
   ```bash
   # Update ARM64 prebuilts
   ANDROID_BUILD_TOP=/mnt/extended/grapheneos-17 ARCH=arm64 common/update_generic_prebuilts.sh

   # Update x86_64 prebuilts
   ANDROID_BUILD_TOP=/mnt/extended/grapheneos-17 ARCH=x86_64 common/update_generic_prebuilts.sh
   ```
   **Destination paths in AOSP**:
   - `kernel/prebuilts/common-modules/virtual-device/6.18/arm64/`
   - `kernel/prebuilts/common-modules/virtual-device/6.18/x86-64/`
   - `device/google/cuttlefish_prebuilts/kernel/6.18/`

---

### 2.2 Microdroid 6.18 (pVM Micro-OS Kernel)

Microdroid is the lightweight Android guest operating system powering protected virtual machines (pVMs) via the Android Virtualization Framework (AVF).

- **Source Manifest Repository**: `https://github.com/GrapheneOS/kernel_manifest-6.18.git`
- **Branch**: `17`
- **Build Engine**: Google Kleaf / Bazel (`tools/bazel`)

#### Pipeline Workflow
1. **Compilation via Bazel**:
   - ARM64 Microdroid Distribution:
     ```bash
     tools/bazel run //common:kernel_aarch64_microdroid_dist --config=stamp -- --wipe_destdir --destdir=microdroid_dist_arm64
     ```
   - x86_64 Microdroid Distribution:
     ```bash
     tools/bazel run //common:kernel_x86_64_microdroid_dist --config=stamp -- --wipe_destdir --destdir=microdroid_dist_x86_64
     ```
2. **Prebuilt Tree Integration**:
   ```bash
   ANDROID_BUILD_TOP=/mnt/extended/grapheneos-17 ARCH=arm64 common/update_microdroid_prebuilts.sh
   ANDROID_BUILD_TOP=/mnt/extended/grapheneos-17 ARCH=x86_64 common/update_microdroid_prebuilts.sh
   ```
   **Destination path in AOSP**:
   - `packages/modules/Virtualization/microdroid/kernel/` (distributes `kernel`, `microdroid_kernel.img`, modules, and DTBOs for pVM init).

---

### 2.3 6th Through 9th Generation Pixel Kernels (Tensor G1–G4, 6.1 LTS)

Pixel 6 (`oriole`), 6 Pro (`raven`), 6a (`bluejay`), 7 (`panther`), 7 Pro (`cheetah`), 7a (`lynx`), Tablet (`tangorpro`), Fold (`felix`), 8 (`shiba`), 8 Pro (`husky`), 8a (`akita`), 9 (`tokay`), 9 Pro (`caiman`), 9 Pro XL (`komodo`), 9 Pro Fold (`comet`), and 10a (`stallion`).

- **GitLab Source Tree**: `https://gitlab.com/grapheneos/kernel_pixel_6.1.git`
- **Branches**:
  - `17-qpr2` (Tensor G1 through Tensor G4: GS101, GS201, Zuma, Zumapro)
  - `17-qpr2-stallion` (Tensor G4 variant for Pixel 10a `stallion`)
- **Build Engine**: Kleaf build scripts wrapping Bazel

#### Codename Mapping Table
| Commercial Name | Device Codename | Kernel Codename Target | Platform Prebuilt Directory |
|:---|:---|:---|:---|
| Pixel 6 | `oriole` | `raviole` | `device/google/raviole-kernels/6.1/grapheneos/` |
| Pixel 6 Pro | `raven` | `raviole` | `device/google/raviole-kernels/6.1/grapheneos/` |
| Pixel 6a | `bluejay` | `bluejay` | `device/google/bluejay-kernels/6.1/grapheneos/` |
| Pixel 7 | `panther` | `pantah` | `device/google/pantah-kernels/6.1/grapheneos/` |
| Pixel 7 Pro | `cheetah` | `pantah` | `device/google/pantah-kernels/6.1/grapheneos/` |
| Pixel 7a | `lynx` | `lynx` | `device/google/lynx-kernels/6.1/grapheneos/` |
| Pixel Tablet | `tangorpro` | `tangorpro` | `device/google/tangorpro-kernels/6.1/grapheneos/` |
| Pixel Fold | `felix` | `felix` | `device/google/felix-kernels/6.1/grapheneos/` |
| Pixel 8 | `shiba` | `shusky` | `device/google/shusky-kernels/6.1/grapheneos/` |
| Pixel 8 Pro | `husky` | `shusky` | `device/google/shusky-kernels/6.1/grapheneos/` |
| Pixel 8a | `akita` | `akita` | `device/google/akita-kernels/6.1/grapheneos/` |
| Pixel 9 | `tokay` | `caimito` | `device/google/caimito-kernels/6.1/grapheneos/` |
| Pixel 9 Pro | `caiman` | `caimito` | `device/google/caimito-kernels/6.1/grapheneos/` |
| Pixel 9 Pro XL | `komodo` | `caimito` | `device/google/caimito-kernels/6.1/grapheneos/` |
| Pixel 9 Pro Fold | `comet` | `comet` | `device/google/comet-kernels/6.1/grapheneos/` |
| Pixel 10a | `stallion` | `stallion` | `device/google/stallion-kernels/6.1/grapheneos/` |

#### Compilation Protocol
```bash
git clone https://gitlab.com/grapheneos/kernel_pixel_6.1.git -b 17-qpr2 --recurse-submodules /mnt/extended/kernel/pixel_6.1
cd /mnt/extended/kernel/pixel_6.1

# Execute Kleaf build target (e.g. caimito for Pixel 9 series)
KLEAF_REPO_MANIFEST=aosp_manifest.xml ./build_caimito.sh

# Deploy prebuilt outputs to GrapheneOS OS tree
mkdir -p /mnt/extended/grapheneos-17/device/google/caimito-kernels/6.1/grapheneos/
cp -a out/caimito/dist/* /mnt/extended/grapheneos-17/device/google/caimito-kernels/6.1/grapheneos/
```

---

### 2.4 10th Generation Pixel Kernels (Tensor G5, Laguna 6.18 LTS)

Pixel 10 (`frankel`), Pixel 10 Pro (`blazer`), Pixel 10 Pro XL (`mustang`), and Pixel 10 Pro Fold (`rango`).

- **GitHub Source Tree**: `https://github.com/GrapheneOS/kernel_pixel.git`
- **Branch**: `17-qpr2-muzel`
- **Kernel Base**: Linux 6.18 LTS GKI + Laguna SOC Driver Tree

#### Codename Mapping Table
| Commercial Name | Device Codename | Kernel Target Name | Platform Prebuilt Directory |
|:---|:---|:---|:---|
| Pixel 10 | `frankel` | `muzel` | `device/google/laguna-kernels/6.18/grapheneos/muzel` |
| Pixel 10 Pro | `blazer` | `muzel` | `device/google/laguna-kernels/6.18/grapheneos/muzel` |
| Pixel 10 Pro XL | `mustang` | `muzel` | `device/google/laguna-kernels/6.18/grapheneos/muzel` |
| Pixel 10 Pro Fold | `rango` | `rango` | `device/google/laguna-kernels/6.18/grapheneos/rango` |

#### Compilation Protocol
```bash
git clone https://github.com/GrapheneOS/kernel_pixel.git -b 17-qpr2-muzel /mnt/extended/kernel/pixel_6.18
cd /mnt/extended/kernel/pixel_6.18

# Sync dependent sub-trees
./sync.sh

# Execute Laguna Kleaf build target
./build_muzel.sh --repo_manifest="$(realpath .)":"$(realpath aosp_manifest.xml)"

# Deploy prebuilt outputs
mkdir -p /mnt/extended/grapheneos-17/device/google/laguna-kernels/6.18/grapheneos/muzel
cp -a out/muzel/dist/* /mnt/extended/grapheneos-17/device/google/laguna-kernels/6.18/grapheneos/muzel/
```

---

## 3. Vanadium & Synergy with Antimony (`yubi-OS/chromium-provenance`)

### 3.1 Vanadium Architecture & Build Pipeline

Vanadium is GrapheneOS's privacy- and security-hardened Chromium fork providing the default system WebView and standalone browser. It leverages GrapheneOS's memory allocator (`hardened_malloc`), enforces strict Control Flow Integrity (`is_cfi = true`), strips Google telemetry/sync dependencies, and isolates renderers in hardened seccomp/bpf sandboxes.

- **Upstream Repository**: `https://github.com/GrapheneOS/Vanadium`
- **Production Reference Tag**: `158.0.8127.42.0` (as of November 2026)
- **AOSP Target Locations**:
  - Browser & Configuration: `external/vanadium/prebuilt/arm64/`
  - System WebView Provider: `external/chromium-webview/` (or `external/vanadium`)

```
Vanadium Source Tree Structure:
Vanadium/
├── args.gn                 # Canonical GN build configuration
├── generate-release        # apksigner automation wrapper
├── patches/                # Downstream security/privacy patches
└── vanadium.keystore       # PKCS#12 RSA-4096 release signing key
```

#### Step-by-Step Build & Signing Protocol
1. **Keystore Generation (First Run / CI Secret Injection)**:
   ```bash
   keytool -genkey -v \
     -keystore /mnt/extended/keys/vanadium.keystore \
     -storetype pkcs12 \
     -alias vanadium \
     -keyalg RSA \
     -keysize 4096 \
     -sigalg SHA512withRSA \
     -validity 10000 \
     -dname "cn=GrapheneOS"
   ```
2. **Calculate Certificate SHA-256 Digest**:
   ```bash
   CERT_DIGEST=$(keytool -export-cert -alias vanadium -keystore /mnt/extended/keys/vanadium.keystore -storepass:env KEYSTORE_PASS | sha256sum | awk '{print $1}')
   ```
   *Note*: `config_apk_certdigest` must match this hash; otherwise Android's Package Manager rejects configuration updates from `VanadiumConfig`.
3. **Chromium Source Synchronization**:
   ```bash
   mkdir -p /mnt/extended/vanadium-build
   cd /mnt/extended/vanadium-build
   git clone https://github.com/GrapheneOS/Vanadium.git -b 158.0.8127.42.0
   cd Vanadium

   # Fetch Chromium codebase
   gclient config --unmanaged https://chromium.googlesource.com/chromium/src.git
   gclient sync --nohooks

   cd src
   git fetch --tags
   git checkout 158.0.8127.42

   # Apply GrapheneOS hardening patches
   git am --whitespace=nowarn --keep-non-patch ../patches/*.patch

   # Sync complete toolchain and dependencies
   gclient sync -D --with_branch_heads --with_tags --jobs $(nproc)
   ```
4. **Build Arguments Configuration (`out/Default/args.gn`)**:
   ```gn
   target_os = "android"
   target_cpu = "arm64"
   is_official_build = true
   is_debug = false
   is_component_build = false
   symbol_level = 0
   is_cfi = true
   use_siso = true
   proprietary_codecs = true
   ffmpeg_branding = "Chrome"

   # Package Names & Certificate Digest
   chrome_public_manifest_package = "app.vanadium.browser"
   system_webview_package_name = "app.vanadium.webview"
   trichrome_library_package = "app.vanadium.trichromelibrary"
   config_apk_package = "app.vanadium.config"
   config_apk_certdigest = "REPLACE_WITH_CALCULATED_CERT_DIGEST"
   ```
5. **Autoninja Compilation**:
   ```bash
   chrt -b 0 autoninja -C out/Default/ \
     vanadium_webview_apk \
     vanadium_browser_apk \
     vanadium_config_apk
   ```
6. **Signing & Release Bundling**:
   ```bash
   export KEYSTORE=/mnt/extended/keys/vanadium.keystore
   echo "$KEYSTORE_PASS" | ../generate-release out
   ```
   Generated artifacts in `out/Default/apks/release/`:
   - `TrichromeChrome.apk` (or `vanadium_browser.apk`)
   - `TrichromeWebView.apk` (or `vanadium_webview.apk`)
   - `TrichromeLibrary.apk`
   - `VanadiumConfig.apk`
7. **Platform Placement**:
   ```bash
   mkdir -p /mnt/extended/grapheneos-17/external/vanadium/prebuilt/arm64/
   cp out/Default/apks/release/*.apk /mnt/extended/grapheneos-17/external/vanadium/prebuilt/arm64/
   ```

---

### 3.2 Synergy with `yubi-OS/chromium-provenance` (Antimony)

Our team maintains `yubi-OS/chromium-provenance` (Antimony), an ARM64 Chromium build series implementing **ADR-000 fail-closed provenance gating** on the `ubuntu` HIGH-MEM runner (`/home/ubuntu/chromium-build/src`). 

```
                                  PROVENANCE GATING INTEGRATION MODES
                                  
      [ Strategy A: Unified Layering ]                 [ Strategy B: Dual WebView Provider ]
      
      Chromium 158 Base Tree                            Frameworks Base Res
               │                                                 │
        (git am patches/)                               (config_webview_packages.xml)
               │                                                 │
      ┌────────┴────────┐                               ┌────────┴────────┐
      ▼                 ▼                               ▼                 ▼
GrapheneOS         yubi-OS                      Vanadium WebView   Antimony WebView
Hardening          ADR-000 Provenance           (Standard Safe)    (High-Assurance Gated)
      │                 │                               │                 │
      └────────┬────────┘                               └────────┬────────┘
               ▼                                                 ▼
      Unified Antimony OS Browser                        User Selectable Engine
      (app.vanadium.browser)                             (Developer Options Switch)
```

There are two primary integration strategies for Antimony within GrapheneOS:

#### Strategy A: Layer Antimony Provenance Gating Directly onto Vanadium
- **Concept**: Treat ADR-000 provenance-gate patches (patches `0001` through `0019` in `yubi-OS/chromium-provenance`) as additional patches applied during step 3 of the Vanadium build pipeline.
- **Benefits**:
  - Retains all Vanadium hardening (CFI, hardened_malloc compatibility, network permission switches).
  - Embeds fail-closed verification of downloaded artifacts and origin provenance directly into the default browser and WebView.
  - Zero changes required to AOSP framework configuration.
- **Implementation**:
  ```bash
  # Inside Vanadium/src after applying ../patches/*.patch:
  git -c safe.directory=/home/ubuntu/chromium-build/src am /home/ubuntu/chromium-provenance/patches/*.patch
  ```

#### Strategy B: Whitelist Antimony as an Alternate WebView Provider
- **Concept**: Maintain Vanadium as the default WebView while introducing Antimony (`org.yubios.antimony.webview`) as a registered alternate WebView provider in AOSP frameworks.
- **AOSP Configuration File**: `frameworks/base/core/res/res/xml/config_webview_packages.xml`
- **XML Modification**:
  ```xml
  <webviewproviders>
      <!-- Default Vanadium WebView -->
      <webviewprovider
          availableByDefault="true"
          description="Vanadium WebView"
          packageName="app.vanadium.webview" />

      <!-- High-Assurance Antimony WebView with ADR-000 Provenance -->
      <webviewprovider
          availableByDefault="false"
          description="Antimony Provenance-Gated WebView"
          packageName="org.yubios.antimony.webview" />
  </webviewproviders>
  ```
- **Infrastructure Reuse**:
  - The `ubuntu` runner already holds `/home/ubuntu/chromium-build/src` with `gn-cipd`, ninja, clang, sysroots, and target definitions for ARM64.
  - We can generate the standalone `org.yubios.antimony.webview` package directly on `/mnt/extended`, package it into `external/antimony/prebuilt/arm64/`, and give users the choice in Developer Options -> "WebView Implementation".

---

## 4. Standalone SDK & Prebuilt Apps

The official GrapheneOS apps are independent Gradle-based Android projects built using modern Android Gradle Plugin (AGP) and Java/Kotlin toolchains. They do not use the legacy AOSP SDK tree (`prebuilts/sdk`); instead, they depend on an isolated Standalone Android SDK bootstrap.

### 4.1 Standalone Android SDK Bootstrap on `/mnt/extended`

The official GrapheneOS build documentation requires a deterministic bootstrap of command-line tools:

```bash
#!/usr/bin/env bash
set -euo pipefail

export ANDROID_HOME="/mnt/extended/android/sdk"
BOOTSTRAP_DIR="$ANDROID_HOME/bootstrap"
mkdir -p "$BOOTSTRAP_DIR"
cd "$BOOTSTRAP_DIR"

# 1. Download official commandlinetools
curl -O https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip

# 2. Strict SHA-256 integrity verification
echo "2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258  commandlinetools-linux-11076708_latest.zip" | sha256sum -c

# 3. Unpack and bootstrap latest cmdline-tools
unzip -q commandlinetools-linux-11076708_latest.zip
./cmdline-tools/bin/sdkmanager 'cmdline-tools;latest' --sdk_root="$ANDROID_HOME"

cd "$ANDROID_HOME"
rm -rf "$BOOTSTRAP_DIR"

# 4. Set PATH
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# 5. Accept licenses deterministically
yes | sdkmanager --licenses > /dev/null

# 6. Install required components
sdkmanager \
  "platform-tools" \
  "build-tools;36.0.0" \
  "platforms;android-36" \
  "platforms;android-37" \
  "ndk;29.0.14206865"
```

---

### 4.2 Standalone App Catalog & Build Matrix

All apps reside in dedicated GitHub repositories under `https://github.com/GrapheneOS/`:

| App Name | Source Repository | Language Stack | Build Mechanism | AOSP Prebuilt Destination |
|:---|:---|:---|:---|:---|
| **AppStore** | `GrapheneOS/AppStore` | Kotlin, Java | `./gradlew assembleRelease` | `packages/apps/AppStore/` |
| **Auditor** | `GrapheneOS/Auditor` | Kotlin, C++ | `./gradlew assembleRelease` | `packages/apps/Auditor/` |
| **Camera** | `GrapheneOS/Camera` | Kotlin, CameraX | `./gradlew assembleRelease` | `packages/apps/Camera/` |
| **PdfViewer** | `GrapheneOS/PdfViewer` | Kotlin, Compose, pdf.js | `./gradlew assembleRelease` | `packages/apps/PdfViewer/` |
| **AppCompatConfig** | `GrapheneOS/AppCompatConfig` | Kotlin, XML | `./gradlew assembleRelease` | `packages/apps/AppCompatConfig/` |
| **GmsCompatConfig** | `GrapheneOS/GmsCompatConfig` | Kotlin, Data | `./gradlew assembleRelease` | `packages/apps/GmsCompatConfig/` |
| **TalkBack** | `GrapheneOS/talkback` | Java, C++ | `./build.sh` | `packages/apps/TalkBack/` |

#### Key App Details
- **AppStore**: Client for the GrapheneOS secure app repository. Supports delta updates, Brotli compression, and TLS key pinning (pinned through October 2027). Target API: 37.
- **Auditor**: Hardware-backed attestation and intrusion detection using the device HSM/Secure Element. Interrogates Android Keystore attestation certificates and verifies verified boot status, OS version, and lock state.
- **Camera**: Custom privacy-focused camera replacing AOSP camera. Uses AndroidX CameraX, strips EXIF metadata on demand, removes network access permissions.
- **PdfViewer**: Fully sandboxed, zero-permission viewer. Uses `pdf.js` inside a restricted WebView with strict CSP, rendered in Jetpack Compose / Material 3.
- **AppCompatConfig**: Distributes per-package exploit mitigation switches (e.g., toggling hardened_malloc off for anti-tamper apps like Uber, suppressing native debugging popups).
- **GmsCompatConfig**: Houses the dynamic compatibility definitions, IPC hooks, and location/auth shims powering sandboxed Google Play.
- **TalkBack**: Cleaned fork of Android Accessibility TalkBack, repaired to build without Google Play dependencies. Built via `./build.sh` and signed with the OS releasekey.

---

### 4.3 Gradle Wrapper Integrity Verification & Determinism

GrapheneOS mandates pinning the Gradle distribution zip hash via `--gradle-distribution-sha256-sum`. In CI pipelines, we must enforce this check before invoking `./gradlew` to defeat wrapper poisoning:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Gradle 8.10.2 Official SHA-256 Checksum
GRADLE_VERSION="8.10.2"
GRADLE_SHA256="31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26"

# Verify wrapper distribution checksum declaration
grep -q "distributionSha256Sum=${GRADLE_SHA256}" gradle/wrapper/gradle-wrapper.properties || {
  echo "ERROR: gradle-wrapper.properties distributionSha256Sum mismatch or missing!"
  exit 1
}

# Clean reproducible build with system timestamps pinned
export SOURCE_DATE_EPOCH=1732000000
./gradlew clean assembleRelease --no-daemon --offline || ./gradlew clean assembleRelease --no-daemon
```

---

## 5. GitHub Actions CI Implementation for Stream 3 on `ubuntu`

The pipeline is implemented as a modular GitHub Actions workflow targeting the self-hosted `ubuntu` runner (`runs-on: [self-hosted, linux, X64, ubuntu]`), staging all scratch spaces on `/mnt/extended`.

```yaml
name: GrapheneOS Stream 3 Prebuilts
on:
  workflow_dispatch:
    inputs:
      component:
        description: 'Component to build'
        required: true
        type: choice
        options:
          - all
          - kernels-gki
          - kernels-pixel-6.1
          - kernels-pixel-6.18
          - vanadium
          - standalone-apps

jobs:
  build-kernels:
    if: inputs.component == 'all' || startsWith(inputs.component, 'kernels-')
    runs-on: [self-hosted, linux, X64, ubuntu]
    steps:
      - name: Check Workspace Disk Space
        run: |
          df -h /mnt/extended
          mkdir -p /mnt/extended/ci-kernels

      - name: Build GKI & Microdroid 6.18
        if: inputs.component == 'all' || inputs.component == 'kernels-gki'
        run: |
          cd /mnt/extended/ci-kernels
          mkdir -p gki-6.18 && cd gki-6.18
          repo init -u https://github.com/GrapheneOS/kernel_manifest-6.18.git -b 17 --depth=1
          repo sync -c -j$(nproc)
          
          # Build GKI
          ARCH=aarch64 common/build_generic.sh
          ARCH=x86_64 common/build_generic.sh
          
          # Build Microdroid via Bazel
          tools/bazel run //common:kernel_aarch64_microdroid_dist --config=stamp -- --wipe_destdir --destdir=dist_microdroid_arm64
          tools/bazel run //common:kernel_x86_64_microdroid_dist --config=stamp -- --wipe_destdir --destdir=dist_microdroid_x86_64

  build-vanadium:
    if: inputs.component == 'all' || inputs.component == 'vanadium'
    runs-on: [self-hosted, linux, X64, ubuntu]
    steps:
      - name: Setup Vanadium & Chromium
        run: |
          mkdir -p /mnt/extended/vanadium
          cd /mnt/extended/vanadium
          # Integration with /home/ubuntu/chromium-build tools
          export PATH="/home/ubuntu/chromium-build/gn-cipd:$PATH"
          echo "Building Vanadium 158.0.8127.42.0 on /mnt/extended"

  build-apps:
    if: inputs.component == 'all' || inputs.component == 'standalone-apps'
    runs-on: [self-hosted, linux, X64, ubuntu]
    steps:
      - name: Setup Standalone Android SDK
        run: |
          export ANDROID_HOME="/mnt/extended/android/sdk"
          mkdir -p "$ANDROID_HOME"
          # Bootstrap commandlinetools-linux-11076708_latest.zip

      - name: Build Auditor & AppStore
        run: |
          echo "Building standalone APKs with pinned Gradle wrappers"
```

---

## 6. Verification Checklist & Concrete Next Steps

1. **Kernel Manifest Alignment**: Confirm that `GrapheneOS/kernel_manifest-6.18` branch `17` is used for generic GKI & Microdroid, while Tensor devices use `kernel_pixel_6.1` (`17-qpr2`) and `kernel_pixel` (`17-qpr2-muzel`).
2. **Vanadium Signing Keys**: Secure the PKCS#12 RSA-4096 key (`vanadium.keystore`) on the runner under `/mnt/extended/keys/` and inject `config_apk_certdigest` into `args.gn`.
3. **Antimony Overlay Staging**: Test Strategy A by applying `yubi-OS/chromium-provenance` patches directly to Chromium 158 tag within Vanadium to yield a unified fail-closed browser.
4. **Standalone SDK Cache**: Seed `/mnt/extended/android/sdk` with Build-Tools 36.0.0 and NDK 29.0.14206865 once so standalone app builds run entirely offline without recurring Google downloads.
