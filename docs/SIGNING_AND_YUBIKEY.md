# Stream 4 Deep-Research Report: Release Signing Keys, AVB Verified Boot, OTA Update Server, Reproducibility & yubi-OS YubiKey Root-of-Trust Integration

**Target System:** GrapheneOS (`https://grapheneos.org/build`) on `yubi-OS/grapheneOS`  
**Execution Environment:** Self-hosted `ubuntu` CI runner (`/mnt/extended`)  
**Core Identity Contract:** yubiOS Root-of-Trust ("The YubiKey is the sole, un-exportable root of trust")  
**Date:** November 19, 2026  

---

## Executive Summary

Stream 4 establishes the cryptographic and distribution boundary for `yubi-OS/grapheneOS`. While AOSP and standard upstream GrapheneOS builds produce unsigned or testkey-signed images during the initial `m target-files-package` compilation pass, a production operating system depends fundamentally on:
1. An uncompromised, authenticated cryptographic signing hierarchy spanning Android Verified Boot 2.0 (AVB), APK/APEX certificates, and factory image archives.
2. An isolated, zero-footprint memory environment during key unsealing (`tmpfs` / `/dev/shm`, disabled swap) to prevent persistent disk leakage.
3. Strict decoupling from official upstream infrastructure (`packages/apps/Updater` configuration and certificate pinning override) to avert destructive client-side infinite verification loops.
4. Deterministic, bit-for-bit reproducibility anchored by timestamp and incremental version pinning, verified via `diffoscope` and attested via SLSA / Sigstore / cosign.
5. Direct integration with yubiOS's primary architectural thesis: anchoring release signing and attestation directly to hardware security tokens (YubiKey PIV and FIDO2/WebAuthn), bridging GrapheneOS's remote hardware attestation (`Auditor`) into the yubiOS ecosystem.

---

## 1. Complete GrapheneOS Signing Key Hierarchy (`keys/<device>/`)

GrapheneOS release signing operates strictly downstream of the OS compile step. Upstream builds target files using the default AOSP public test keys (`build/make/target/product/security/`). Before deployment, `script/generate-release.sh` ingests `keys/<device>/` to resign all components.

```
keys/<device>/
├── releasekey.{x509.pem,pk8}      # Root OS release key (default APKs, APEX container payloads)
├── platform.{x509.pem,pk8}        # Core system apps (SystemUI, Settings, core services)
├── shared.{x509.pem,pk8}          # Shared user ID UID group apps (Contacts, Media Provider)
├── media.{x509.pem,pk8}           # Media/gallery processes, download manager
├── networkstack.{x509.pem,pk8}    # Modular network stack components, CaptivePortalLogin
├── bluetooth.{x509.pem,pk8}       # Bluetooth stack / Bluetooth.apk
├── sdk_sandbox.{x509.pem,pk8}     # Android 14+ Privacy Sandbox process isolation
├── gmscompat_lib.{x509.pem,pk8}   # GrapheneOS Sandboxed Google Play compatibility layer
├── nfc.{x509.pem,pk8}             # Near Field Communication stack / Secure Element service
├── avb.pem                        # 4096-bit RSA PKCS#8 private key for AVB 2.0 (vbmeta)
├── avb_pkmd.bin                   # AVB Public Key Metadata (pre-extracted for bootloader)
└── id_ed25519{,.pub}              # OpenSSH Ed25519 key for factory image archive signatures
```

### 1.1 The 9 APK/APEX Key Pairs

Generated using `development/tools/make_key <name> "/CN=GrapheneOS/"`:
- **`releasekey`**: Signs fallback system packages, recovery image, and outer APEX container packages (`com.android.*.apex`). Also signs payload contents for APEX components where independent upstream signing is not utilized.
- **`platform`**: Signs applications running with system UID (`android:sharedUserId="android.uid.system"`). Grants access to privileged system APIs, SELinux `platform_app` context, and platform permission whitelist.
- **`shared`**: Signs applications sharing data/processes within `android.uid.shared` (e.g., Contacts, Home, UserDictionary).
- **`media`**: Signs packages in `android.uid.media` subsystem (e.g., MediaProvider, DownloadManager, external storage providers).
- **`networkstack`**: Signs `NetworkStack.apk`, `NetworkStackNext.apk`, and captive portal components. Crucial for permission `android.permission.MAINLINE_NETWORK_STACK`.
- **`bluetooth`**: Signs `Bluetooth.apk` and Bluetooth framework packages (`android.uid.bluetooth`).
- **`sdk_sandbox`**: Introduced in Android 14+ for Privacy Sandbox isolation. Enforces strict process isolation for third-party advertising/tracking SDKs outside application processes.
- **`gmscompat_lib`**: Unique to GrapheneOS. Signs the compatibility shim that enables unmodified Google Play Services to execute strictly unprivileged within standard sandboxed user storage.
- **`nfc`**: Signs NFC services (`com.android.nfc`) and card emulation / secure element applets.

**At-Rest Encryption:**
`development/tools/make_key` and GrapheneOS's `script/encrypt-keys` enforce PKCS#8 DER formatting with:
- Key Derivation: `scrypt` (memory-hard, resistant to FPGA/ASIC cracking).
- Cipher: AES-256-CBC (`openssl pkcs8 -topk8 -outform DER -scrypt`).
- Passphrase uniformity: All 9 APK keys and `avb.pem` must share the exact same passphrase for headless unsealing by `script/decrypt-keys`.

### 1.2 Android Verified Boot 2.0 (AVB) Key Architecture

- **`avb.pem`**: 4096-bit RSA private key in PKCS#8 format. Upstream AVB enforces `SHA256_RSA4096` algorithm across modern Google Tensor Pixels (Tensor G1 through Tensor G4+):
  ```bash
  openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out avb.pem
  ```
- **`avb_pkmd.bin` (Public Key Metadata)**:
  Extracted directly via the AOSP AVB tool:
  ```bash
  external/avb/avbtool.py extract_public_key --key avb.pem --output avb_pkmd.bin
  ```
  `avb_pkmd.bin` is binary metadata structured by `AvbRSAPublicKeyHeader` containing the RSA modulus $N$, public exponent $e$, and pre-computed Montgomery arithmetic parameters ($R^2 \bmod N$, $-N^{-1} \bmod 2^{64}$).
- **Root-of-Trust Handshake on Device**:
  Flashing this key to the device sets the user-custom root of trust:
  ```bash
  fastboot flash avb_custom_key avb_pkmd.bin
  ```
  Upon `fastboot flashing lock`, Google Tensor Titan M2 / bootloader firmware computes $\text{SHA-256}(\text{avb\_pkmd.bin})$. The resulting 32-byte hash (64 hex characters) is burned into hardware tamper-evident non-volatile storage as the device's custom `verifiedBootKey`.

### 1.3 Factory Image OpenSSH Signing Key (`id_ed25519`)

GrapheneOS factory images are signed using OpenSSH Ed25519 signatures:
```bash
ssh-keygen -t ed25519 -f keys/<device>/id_ed25519
```
During release finalization (`script/generate-release.sh`), the script runs:
```bash
ssh-keygen -Y sign -n "factory images" -f "$KEY_DIR/id_ed25519" $DEVICE-install-$BUILD_NUMBER.zip
```
This produces `$DEVICE-install-$BUILD_NUMBER.zip.sig`. When flashing via GrapheneOS's WebUSB installer or CLI tools, the signature is verified against the published public key (`id_ed25519.pub`), authenticating the factory archive prior to unpack and flash.

### 1.4 Memory Hygiene & Anti-Exfiltration Guarantees in CI

On the `ubuntu` CI runner (`/mnt/extended`), handling decrypted private key material poses persistent storage leakage risks:
1. **`tmpfs` Execution Boundary**:
   `script/decrypt-keys` and `script/generate-release.sh` mandate unsealing into RAM backed by `/dev/shm` (or dedicated `tmpfs`):
   ```bash
   KEY_DIR=$(mktemp -d /dev/shm/generate-release.XXXXXXXXXX)
   trap "rm -rf \"$KEY_DIR\" && rm -f \"$PWD/$RELEASE_OUT/keys\"" EXIT
   cp "$PERSISTENT_KEY_DIR"/* "$KEY_DIR"
   script/decrypt-keys "$KEY_DIR"
   ```
   Unencrypted keys (`.pk8`, `avb.pem`) exist exclusively inside volatile memory and are purged on script exit.
2. **Mandatory Swap Disabling (`swapoff -a`)**:
   If the host runner triggers swapping under high memory pressure (e.g., during parallel image compression or Java heap spikes during `sign_target_files_apks`), pages from `/dev/shm` can be paged out to disk partitions or swap files on `/mnt/extended`.
   - **Enforcement Rule:** CI release jobs must invoke `sudo swapoff -a` prior to `decrypt-keys` and verify swap status via `/proc/swaps`. If swapping is strictly necessary, an ephemeral dm-crypt swap (`cryptsetup open --type plain --key-file /dev/urandom ...`) must be configured so memory pages are cryptographically discarded upon reboot.

---

## 2. Release Packaging, Delta Updates & Mandatory Updater URL Override

### 2.1 The Updater URL Hazard & `config.xml` Override

In AOSP/GrapheneOS, `packages/apps/Updater` handles background system updates. The client polls the update server, parses version metadata, checks delta update availability, downloads payloads, streams them into `system_update_engine` (A/B dynamic partitioning), and verifies update signatures against the installed OS keys.

**The Loop/DoS Vulnerability:**
In `platform_packages_apps_Updater`, the default configuration points to upstream:
```xml
<!-- packages/apps/Updater/res/values/config.xml -->
<resources>
    <string name="url" translatable="false">https://releases.grapheneos.org/</string>
    <string name="channel_default" translatable="false">stable</string>
</resources>
```
If an operator builds GrapheneOS with `OFFICIAL_BUILD=true` (which compiles and bundles the Updater app) without overriding `config.xml`:
1. The custom device boots with private keys $K_{\text{custom}}$.
2. The Updater polls `https://releases.grapheneos.org/`.
3. Upstream serves an official metadata file signed with $K_{\text{official}}$.
4. The Updater downloads the official OTA payload.
5. `update_engine` attempts verification against the local recovery/OS certificates ($K_{\text{custom}}$).
6. **Verification fails:** Signature mismatch.
7. The Updater discards the downloaded update as corrupt and immediately triggers another poll/download attempt.
8. **Result:** An aggressive, infinite download loop that burns device bandwidth/battery and performs an inadvertent Distributed Denial of Service (DDoS) against GrapheneOS's release CDN.

**Mandatory Override Specification:**
In `yubi-OS/grapheneOS`, an overlay or sed replace is strictly enforced before build:
```xml
<!-- packages/apps/Updater/res/values/config.xml override -->
<resources>
    <string name="url" translatable="false">https://ota.yubios.org/</string>
    <string name="channel_default" translatable="false">stable</string>
    <string name="network_type_default" translatable="false">1</string>
    <string name="battery_not_low_default" translatable="false">true</string>
    <string name="requires_charging_default" translatable="false">false</string>
    <string name="idle_reboot_default" translatable="false">false</string>
</resources>
```
Additionally, `res/xml/network_security_config.xml` contains HPKP/pin-set rules for Let's Encrypt / ISRG Root certs. When re-pointing to `ota.yubios.org`, the certificate pin-set must either be updated with the domain's CA root or adjusted to accept the system trust store.

### 2.2 Release Packaging Pipeline

The release pipeline executes sequentially after build:
```bash
# 1. Compile build host packaging tools
m otatools-package

# 2. Stage target files into releases/ directory
script/finalize.sh
# Copies:
#   $OUT/obj/PACKAGING/target_files_intermediates/$TARGET_PRODUCT-target_files.zip
#   $ANDROID_HOST_OUT/obj/ETC/otatools-packagelinux_glibc_x86_64_intermediates/otatools-package*

# 3. Generate signed factory images, full OTA, and metadata
script/generate-release.sh <device> <BUILD_NUMBER>

# 4. Generate delta updates (for incremental upgrades)
script/generate-delta.sh <device> <OLD_BUILD_NUMBER> <NEW_BUILD_NUMBER>
```

**Inside `script/generate-release.sh`:**
1. Unpacks `releases/$BUILD_NUMBER/$DEVICE-otatools.zip` into `$RELEASE_OUT`.
2. Decrypts keys into `/dev/shm` and binds `$RELEASE_OUT/keys`.
3. Invokes `sign_target_files_apks`:
   - Re-signs every APK with its dedicated key (`platform`, `media`, `shared`, etc.).
   - Re-signs APEX containers and payloads with `avb.pem` and `releasekey`.
   - Re-signs `vbmeta.img`, `boot.img`, `vendor_boot.img`, and dynamic partitions (`system`, `system_ext`, `product`, `vendor`) with `avb.pem` (`--avb_vbmeta_algorithm SHA256_RSA4096`).
4. Invokes `ota_from_target_files -k keys/releasekey` to produce `$DEVICE-ota_update-$BUILD_NUMBER.zip`.
5. Invokes `script/generate-metadata` on the update zip:
   - Reads `META-INF/com/android/metadata`.
   - Parses `post-build`, `post-timestamp`, `pre-device`.
   - Writes channel files: `$DEVICE-testing`, `$DEVICE-beta`, `$DEVICE-stable`, `$DEVICE-alpha`.
   - Line format: `<incremental_version> <timestamp> <device> <channel>`.
6. Invokes `img_from_target_files` and `fastboot optimize-factory-image` to generate fastboot-flashable `$DEVICE-factory-$BUILD_NUMBER.zip`.
7. Signs factory zip with `id_ed25519`.

### 2.3 Incremental Delta Updates (`generate-delta.sh`)

Delta updates dramatically reduce bandwidth (e.g., from a 2.5 GB full image to 50–150 MB).
```bash
ota_from_target_files -k "$KEY_DIR/releasekey" \
    -i releases/$OLD/release-$DEVICE-$OLD/$DEVICE-target_files.zip \
    releases/$NEW/release-$DEVICE-$NEW/$DEVICE-target_files.zip \
    $DEVICE-incremental-$OLD-$NEW.zip
```
The resulting delta file is named `<device>-incremental-<old_build>-<new_build>.zip`. When the Updater app checks for updates, it inspects its current local `ro.build.version.incremental`. If an incremental package matching `<current>-<target>` exists at the update endpoint, it downloads the incremental file rather than the full OTA update.

### 2.4 Static Update Server Architecture on Cloudflare / Steady Orbit Infra

GrapheneOS's update protocol requires only a static HTTP web server. There is no dynamic backend API.

**Directory Structure at Static Web Root (`https://ota.yubios.org/`):**
```
/
├── tegu-testing
├── tegu-beta
├── tegu-stable
├── tegu-ota_update-2026111900.zip
├── tegu-factory-2026111900.zip
├── tegu-factory-2026111900.zip.sig
├── tegu-incremental-2026111000-2026111900.zip
└── ...
```

**Cloudflare Worker + R2 Architecture:**
- **Storage:** Cloudflare R2 bucket (`yubios-graphene-releases`) stores the multi-gigabyte factory zips and OTA update packages.
- **Worker Router (`ota-worker.ts`):**
  - Serves channel files (`/<device>-stable`, etc.) directly from R2 or Cloudflare KV with zero-latency edge caching (`Cache-Control: public, max-age=300`).
  - Supports HTTP Range requests (`bytes=...`) natively via R2 streaming bindings, essential for resumable A/B OTA downloads in Android `update_engine`.
  - Enforces strict security headers: TLS 1.3 only, HSTS, `Content-Type: application/octet-stream`.

---

## 3. Reproducible Builds & Attestation

### 3.1 Deterministic Source Pinning

AOSP build artifacts embed build time and incremental versioning into system properties (`build.prop`), file modification timestamps, and zip file headers. To reproduce a build bit-for-bit:
```bash
# Extracted from prior build records:
export BUILD_DATETIME=$(cat out/build_date.txt)
export BUILD_NUMBER=$(cat out/build_number.txt)
```
These properties correspond to:
- `ro.build.date.utc`: Epoch seconds integer.
- `ro.build.version.incremental`: Date-based build sequence number (e.g. `2026111900`).

When both variables are set in the environment, the AOSP build system overrides `date`-based generation and enforces fixed timestamps across all compiled filesystem images and packaging routines (`SOURCE_DATE_EPOCH` compliance).

### 3.2 Unsigned vs. Signed Artifact Comparison (`diffoscope`)

Signing modifies:
- APK/APEX signature blocks (v1/v2/v3 APK Signature Schemes).
- AVB hash/hashtree footers and `vbmeta` cryptographic descriptors.
- Filesystem superblock UUIDs and dm-verity Merkle trees.

**Verification Methodology:**
1. **Unsigned Target Files Comparison:** Two independent builders compile from the same git commit and manifests with pinned `BUILD_DATETIME` and `BUILD_NUMBER`. Running `diffoscope target_files_1.zip target_files_2.zip` yields zero binary diffs across all `.img` files, `.jar` files, and binaries before signing.
2. **Signed Release Comparison:** If comparing against a release signed with private keys held elsewhere, exact binary matching is impossible. Verification is achieved by:
   - Stripping APK signature blocks using `apksigner verify --print-certs` and comparing unpacked contents.
   - Using `avbtool verify_image` to check partition hash trees against the root descriptor.
   - Auditing differences strictly to signature payload segments via automated AST/binary diffing.

### 3.3 SLSA Level 3 Provenance & Sigstore / Cosign Attestation

Following yubiOS's `slsa-provenance` and `sigstore-rekor-v2` skills:
1. **In-Toto Attestation Generation:**
   During CI finalization on `ubuntu`, a SLSA v1.0 predicate is generated:
   ```json
   {
     "_type": "https://in-toto.io/Statement/v1",
     "subject": [
       { "name": "tegu-ota_update-2026111900.zip", "digest": { "sha256": "..." } },
       { "name": "tegu-factory-2026111900.zip", "digest": { "sha256": "..." } }
     ],
     "predicateType": "https://slsa.dev/provenance/v1",
     "predicate": {
       "buildDefinition": {
         "buildType": "https://github.com/yubi-OS/grapheneOS/actions/build@v1",
         "externalParameters": { "manifest": "yubi-OS/grapheneOS@...", "device": "tegu" },
         "resolvedDependencies": [ ... ]
       },
       "runDetails": {
         "builder": { "id": "https://github.com/yubi-OS/grapheneOS/runners/ubuntu" }
       }
     }
   }
   ```
2. **Signing & Transparency Log Rekor Anchor:**
   - The provenance statement is signed using Cosign via the runner's OIDC token or a YubiKey PIV key.
   - The signed bundle is submitted to Sigstore / Rekor v2 tiles to prove timestamp, runner identity, and immutability.

---

## 4. yubi-OS Architectural Bridge: YubiKey Root of Trust for GrapheneOS

The defining mandate of yubiOS is: **"The YubiKey is the sole, un-exportable root of trust."** Integrating GrapheneOS into this ecosystem replaces software-held private keys with hardware-enforced primitives across two domains: release signing and device attestation.

```
+-----------------------------------------------------------------------------------+
|                        yubi-OS Hardware Root of Trust                             |
+-----------------------------------------------------------------------------------+
             |                                                  |
  [Release Signing Plane]                             [Device Attestation Plane]
             |                                                  |
     +-------v--------+                                 +-------v--------+
     |   YubiKey 5    |                                 |   YubiKey 5    |
     |   PIV Applet   |                                 | FIDO2 WebAuthn |
     +-------+--------+                                 +-------+--------+
             |                                                  |
    OpenSC / PKCS#11                                     WebAuthn Assertion
             |                                                  |
  +----------v-----------------------+                 +--------v-------------------+
  | avbtool / apksigner Integration  |                 | GrapheneOS Auditor Server  |
  |  - avbtool --signing_helper      |                 |  - StrongBox / TEE quotes  |
  |  - apksigner PKCS11 provider     |                 |  - verifiedBootKey pinned  |
  |  OR                              |                 |  - YubiKey admin root      |
  | fido2-assert hmac-secret unseal  |                 +----------------------------+
  +----------------------------------+
```

### 4.1 Hardware-Backed Release Signing

Standard AOSP scripts expect private keys on the local filesystem. yubiOS provides two distinct operational paths:

#### Approach A: Direct PKCS#11 Hardware Signing (Slot 9c & Retired Slots)

In this pattern, the private keys are generated directly inside the YubiKey's Secure Element (or imported during a formal key ceremony) and flagged as un-exportable.
- **PIV Slot Assignment:**
  - `Slot 9c` (Digital Signature): Dedicated to the AVB Root Key (`avb.pem` RSA-4096 or RSA-2048).
  - `Slots 82–8a` (Retired Key Slots 1–9): Assigned to the 9 APK signing keys (`releasekey`, `platform`, `shared`, etc.).
- **AVB Tool Hardware Helper (`--signing_helper`):**
  `avbtool.py` natively supports delegating raw signature computations to an external binary:
  ```python
  p = subprocess.Popen([signing_helper, algorithm_name, self.key_path],
                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  (pout, perr) = p.communicate(padding_and_hash)
  ```
  We implement a wrapper script `yubikey-avb-signer.sh`:
  ```bash
  #!/usr/bin/env bash
  # yubikey-avb-signer.sh: Signs AVB SHA256 digest using YubiKey PIV Slot 9c
  ALGORITHM="$1"
  KEY_HINT="$2"
  DATA_TO_SIGN=$(cat) # Reads padded hash from stdin

  # Execute raw signature over OpenSC PKCS#11 engine via pkcs11-tool
  pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
              --login --pin "$YUBIKEY_PIN" \
              --sign --id 02 \
              --mechanism RSA-PKCS \
              --input-file <(echo -n "$DATA_TO_SIGN")
  ```
  Invoked during target files signing:
  ```bash
  sign_target_files_apks \
      --avb_vbmeta_key "$PUB_KEY_DIR/avb_pub.pem" \
      --avb_vbmeta_signing_helper /usr/local/bin/yubikey-avb-signer.sh \
      ...
  ```
- **APK Signing via `apksigner` PKCS#11 Keystore:**
  `apksigner` natively supports SunPKCS11 provider configurations:
  ```bash
  # pkcs11_yubikey.cfg
  name = YubiKey
  library = /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
  slotListIndex = 0
  ```
  Signing command:
  ```bash
  apksigner sign --provider-class sun.security.pkcs11.SunPKCS11 \
                 --provider-arg pkcs11_yubikey.cfg \
                 --ks NONE \
                 --ks-type PKCS11 \
                 --ks-key-alias "Certificate for Digital Signature" \
                 target.apk
  ```

#### Approach B: YubiKey FIDO2 `hmac-secret` Passphrase Unsealing (Attended CI Release)

Because batch-signing dozens of APEXes and APKs through hardware token smart-card interfaces can incur USB transfer latency, yubiOS introduces the **FIDO2 HMAC-Secret Key-Wrapping Pattern** (matching yubiOS's LUKS2 and `systemd-homed` enrollment standard):
1. The 9 APK keys and `avb.pem` are encrypted with an ultra-high-entropy master passphrase ($S$).
2. $S$ is sealed using the YubiKey's FIDO2 `hmac-secret` extension (`fido2-assert -m`).
3. During attended release builds on the CI runner, the operator connects their YubiKey:
   ```bash
   # Derive unseal key from YubiKey physical presence + touch
   UNSEAL_KEY=$(fido2-assert -G -h -i "$SALT_FILE" "$CRED_ID" /dev/hidrawX)
   PASSPHRASE=$(openssl enc -d -aes-256-gcm -in sealed_passphrase.enc -K "$UNSEAL_KEY" ...)
   
   # Unseal keys directly into tmpfs
   password="$PASSPHRASE" script/decrypt-keys /dev/shm/signing_keys
   ```
4. Signing proceeds in volatile RAM at full NVMe/CPU speeds.
5. `/dev/shm` is scrubbed and unmounted immediately upon completion.
6. The private keys remain cryptographically inert at rest unless unlocked by physical touch on the YubiKey.

---

### 4.2 Hardware Attestation Verification via GrapheneOS `Auditor` & YubiKey

GrapheneOS features an industry-leading hardware-based attestation system composed of:
1. **Audited Device (Client):** Uses the Pixel's Titan M2 hardware security module / StrongBox Keymaster to generate an asymmetric key pair attested by Google's hardware root certificate.
2. **Auditor App / Server:** Verifies the attestation certificate chain, inspecting:
   - Bootloader state (`LOCKED`).
   - Verified boot status (`VERIFIED`).
   - Operating system patch level and build fingerprint.
   - **`verifiedBootKey`**: The SHA-256 fingerprint of the AVB public key (`avb_pkmd.bin`).

#### Anchoring Custom yubi-OS Releases in Auditor

In `app.attestation.auditor.AttestationProtocol`, the Auditor codebase hardcodes known fingerprints:
```java
// AttestationProtocol.java
private static final ImmutableMap<String, DeviceInfo> fingerprintsNonStock = ImmutableMap
    .<String, DeviceInfo>builder()
    // Upstream GrapheneOS Pixel 8 (Shiba)
    .put("08C860350A9600692D10C8512F7B8E80707757468E8FBFEEA2A870C0A83D6031",
         new DeviceInfo(R.string.device_pixel_8, 100, 100, false, R.string.os_graphene))
    ...
```
When `yubi-OS/grapheneOS` builds with custom AVB keys:
1. Calculate the custom AVB key fingerprint:
   ```bash
   sha256sum keys/<device>/avb_pkmd.bin | awk '{print toupper($1)}'
   # Example: E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
   ```
2. Fork `platform_external_Auditor` and `AttestationServer`:
   - Add the custom SHA-256 fingerprint into `fingerprintsNonStock` mapped to `R.string.os_yubios`.
   - Update `app/src/main/res/values/strings.xml` to declare the OS identity.
3. Deploy a private Attestation Server instance on Steady Orbit / Cloudflare Workers:
   - When the enrolled device periodically attests its hardware state to the server, the server validates that the running operating system is cryptographically signed by the yubi-OS AVB key.
4. **YubiKey Admin Authorization:**
   - Management access to the Attestation Server dashboard (viewing device fleets, attestation status, and health telemetry) requires FIDO2 WebAuthn authentication using the operator's physical YubiKey.
   - If an attestation challenge fails (indicating an unauthorized OS flash, modified bootloader, or tampered system partition), the server triggers an automated revocation event, terminating device access to yubiOS internal services and Tailscale gateways.

---

## 5. Implementation Roadmap for Stream 4 on `yubi-OS/grapheneOS`

| Phase | Milestone | Deliverables / Actions |
|---|---|---|
| **Phase 4.1** | Key Hierarchy Generation | Run `make_key` and `openssl` for target device (`tegu`/`husky`); encrypt keys at rest via `scrypt` + AES-256; store encrypted keyrings in secure vault. |
| **Phase 4.2** | Updater App Customization | Patch `packages/apps/Updater`: change update URL to `https://ota.yubios.org/`; update `network_security_config.xml` domain pins. |
| **Phase 4.3** | Memory-Safe CI Pipeline | Configure self-hosted GitHub Actions workflow on `ubuntu`: allocate `tmpfs` under `/dev/shm`, execute `sudo swapoff -a`, run `finalize.sh` and `generate-release.sh`. |
| **Phase 4.4** | Edge OTA Server Deployment | Deploy Cloudflare Worker + R2 bucket; configure range requests, static channel pointers (`<device>-stable`), and Ed25519 signature serving. |
| **Phase 4.5** | Reproducibility & SLSA Gate | Implement `reproducible-check.sh`: verify bit-for-bit parity against pinned `BUILD_DATETIME` and `BUILD_NUMBER`; sign provenance with Cosign. |
| **Phase 4.6** | YubiKey Root-of-Trust Bridge | Implement `avbtool --signing_helper` OpenSC wrapper for PIV Slot 9c and FIDO2 `hmac-secret` attended unsealing; register `avb_pkmd.bin` fingerprint in custom `Auditor`. |

---

*Report authored for `yubi-OS/grapheneOS` by Sauna AI subagent.*  
*Source references: upstream GrapheneOS build guide, AOSP AVB 2.0 specification, GrapheneOS/script, GrapheneOS/Auditor, and Yubico PIV/FIDO2 technical specifications.*
