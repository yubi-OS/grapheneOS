# Stream 1: Host OS, Packages, `/mnt/extended` Storage Layout, and ARM64 Host vs x86_64 AOSP Toolchain Architecture

**Target**: GrapheneOS 17 (`branch: 17`, tag `2026111800`)  
**Host Runner**: `ubuntu` (Microsoft Surface Laptop 7, Snapdragon X Elite ARM64 `aarch64`, 12 cores, 62 GiB RAM, Ubuntu 26.04.1 LTS / noble/plucky series)  
**Primary Build Filesystem**: `/mnt/extended` (Dedicated NVMe partition mounted for workspace/build tree; root `/` has ~67 GB free)  
**Hardware I/O Guard**: `ubuntu` halts under unthrottled NVMe/git bursts; strict enforcement of `nice -n 19 ionice -c3` and concurrency limits (`-j4` for repo sync, `-j8 -l10` for Soong/Ninja).

---

## 1. Complete Host Package Prerequisites & System Configuration

Building GrapheneOS on Ubuntu/Debian requires packages across five distinct functional domains: source fetching/verification, core AOSP build toolchain, vendor extraction (`adevtool`), browser engine compilation (Vanadium/Chromium), and cryptographic release signing.

### 1.1 Source Fetch & Verification Dependencies
Official upstream reference: [GrapheneOS Build Dependencies](https://grapheneos.org/build#build-dependencies).

```bash
sudo apt update && sudo apt install -y \
  git \
  git-lfs \
  gnupg \
  python3 \
  python3-protobuf \
  protobuf-compiler \
  curl \
  openssh-client \
  ca-certificates
```

* **`repo`**: While Ubuntu provides a `repo` package, GrapheneOS strongly recommends the standalone self-updating launcher from Google to prevent distribution packaging skew:
  ```bash
  sudo curl -o /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
  sudo chmod a+rx /usr/local/bin/repo
  ```
  `repo` uses GPG internally to verify cryptographic signatures of its self-updates and upstream manifests.
* **`git` & `git-lfs`**: Required for checkout and for managing large binary blobs (especially within Chromium/Vanadium trees).
* **`openssh-client`**: Required for verifying GrapheneOS signed git tags and release manifests via `ssh-keygen -Y verify` using `allowed_signers`.

### 1.2 AOSP Build Dependencies (Host-Level, Outside Source Tree)
AOSP relies on prebuilts for compilers and linkers, but depends on the host system for system headers, low-level compression, font rendering (headless OpenJDK), and build-sandboxing utilities:

```bash
sudo apt install -y \
  diffutils \
  libfreetype6 \
  libfreetype6-dev \
  fontconfig \
  fonts-dejavu-core \
  inetutils-tools \
  hostname \
  openssl \
  libssl-dev \
  rsync \
  unzip \
  zip \
  bc \
  bison \
  flex \
  gperf \
  libncurses6 \
  libncurses-dev \
  zlib1g \
  zlib1g-dev \
  liblz4-tool \
  lz4 \
  zstd \
  squashfs-tools \
  e2fsprogs \
  cpio \
  bsdextrautils \
  procps
```

* **`inetutils-tools` / `hostname`**: AOSP build scripts (such as `build/soong/ui/build/sandbox_linux.go`) execute `hostname` inside NsJail sandbox probes to ensure unprivileged user namespace isolation succeeded.
* **`fontconfig`, `libfreetype6`, `fonts-dejavu-core`**: Required by headless OpenJDK (`prebuilts/jdk/jdk21/linux-x86`) during layout compilation and resource generation; without host font engines, headless Java crashes on font metrics queries.
* **`diffutils`, `rsync`, `zip`, `unzip`, `bc`, `bison`, `flex`, `gperf`**: Required for host utility generation, device-tree compiler (`dtc`), SELinux policy compilation (`checkpolicy`), and kernel header extractions.
* **`squashfs-tools`, `e2fsprogs`, `lz4`, `zstd`**: Filesystem tools required by `build/make/tools/releasetools` to generate system, vendor, product, and APEX filesystem images.

### 1.3 `adevtool` Dependencies (Vendor File Extraction)
`adevtool` is GrapheneOS's TypeScript-based tool that downloads official Google Pixel factory images and OTA payloads, extracts proprietary firmware, modem, and vendor HAL binaries, unpacks radio/bootloader images, and generates vendor makefiles for the build tree.

* **Node.js 24 LTS & Corepack / Yarn**:
  Ubuntu system Node.js is often outdated. Debian/Ubuntu package `yarn` is reserved for `cmdtest`. Install Node.js 24 LTS and enable Corepack for Yarn v1/v4:
  ```bash
  # NodeSource or standalone archive for aarch64
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
  sudo apt install -y nodejs
  sudo corepack enable
  ```
  Within the tree, dependencies are initialized with:
  ```bash
  yarn --cwd vendor/adevtool/ install
  ```
* **`python3-protobuf`**: The payload extraction helper `vendor/adevtool/external/extract_android_ota_payload/` requires `google.protobuf` to parse OTA `update_metadata.pb`.

### 1.4 Vanadium (Chromium) Host Dependencies
Vanadium provides the hardened Chromium browser and system WebView:

```bash
sudo apt install -y \
  git-lfs \
  gperf \
  bison \
  flex \
  ninja-build
```

* **Multiarch 32-bit Compatibility**: On standard `x86_64` hosts, Chromium's toolchain requires 32-bit glibc (`libc6:i386`, `libgcc-s1:i386`). On our `aarch64` host running inside an `amd64` container / sysroot, 32-bit multiarch is enabled inside the `amd64` container environment via `dpkg --add-architecture i386`.

### 1.5 Release Signing Dependencies
* **`openssh-client` (`ssh-keygen`)**: Generates Ed25519 factory image release signatures and verifies download artifacts.
* **`openssl` (with `scrypt` KDF support)**: AOSP/GrapheneOS keys (`make_key` and `script/encrypt-keys`) encrypt device signing keys using AES-256 with `scrypt` as the Key Derivation Function (KDF). Standard OpenSSL 3.x on modern Ubuntu natively includes the `scrypt` KDF algorithm.

---

## 2. AOSP & GrapheneOS on an `aarch64` Linux Host (`ubuntu`)

### 2.1 The Fundamental Constraint: Prebuilt x86_64 ELF Binaries in AOSP
Upstream Android Open Source Project and GrapheneOS maintain a hermetic build philosophy where host toolchains are precompiled and checked directly into git repositories under `prebuilts/`. These include:
- `prebuilts/clang/host/linux-x86/`: Clang/LLVM C/C++ compiler suites
- `prebuilts/rust/linux-x86/`: `rustc` compiler and standard libraries
- `prebuilts/go/linux-x86/`: Host Go compiler used to compile Soong itself
- `prebuilts/build-tools/linux-x86/`: Ninja, NsJail, Kati (`ckati`), Toybox, Bison, Flex, Make
- `prebuilts/jdk/jdk21/linux-x86/`: OpenJDK runtime
- `build/soong/soong_ui.bash`: Bootstrap wrapper compiling `soong_ui`

Every one of these binaries is an `ELF 64-bit LSB x86-64` executable. When executed on an unmodified `aarch64` host, the Linux kernel returns `ENOEXEC` (`Exec format error`) immediately.

Furthermore, `build/envsetup.sh` and Soong's host architecture detection query `uname -m`. When `uname -m` outputs `aarch64` or `arm64`, upstream AOSP build scripts abort with:
```
Unknown host arch aarch64
```
or attempt to resolve non-existent paths under `prebuilts/.../linux-arm64/`.

### 2.2 Execution Architecture A: Multiarch + `qemu-user-static` (`binfmt_misc` with `F` Flag) + Rootless Container

To bridge the x86_64 prebuilt execution requirement on `ubuntu` (`aarch64`), the rock-solid strategy is **kernel-level user-mode emulation** paired with an `amd64` container or sysroot.

#### The Mandatory `F` (Fix-Binary) Flag in `binfmt_misc`
The Linux kernel's `binfmt_misc` subsystem matches binary magic headers and routes execution to an interpreter (e.g., `/usr/bin/qemu-x86_64-static`).

In standard `binfmt_misc` configurations without flags, the kernel resolves the interpreter path **lazily at execution time within the mount namespace of the target process**.

**Why this breaks AOSP:**
AOSP's Soong build system uses **NsJail** (`ui/build/sandbox_linux.go`) to isolate build steps. NsJail creates fresh mount namespaces, unshares user namespaces, pivots the root, and mounts isolated `/` structures:
1. When Soong spawns `prebuilts/build-tools/linux-x86/bin/nsjail`, NsJail creates a private mount namespace.
2. Inside that namespace, NsJail executes an `x86_64` binary (such as `clang`, `rustc`, or `ckati`).
3. If `binfmt_misc` was registered without the `F` flag, the kernel attempts to look up `/usr/bin/qemu-x86_64-static` inside the **sandbox's private mount namespace**.
4. Because the AOSP source tree does not copy `qemu-x86_64-static` into its sandbox chroot, the execve fails with:
   ```
   execve(...): No such file or directory
   ```
   causing Soong to fail immediately with `"Build sandboxing disabled due to nsjail error"` or hard abort.

**The Fix:**
Kernel 4.8+ introduced the `F` (`fix-binary`) flag (`--fix-binary yes` in `update-binfmts`). When `F` is set:
- The Linux kernel opens `/usr/bin/qemu-x86_64-static` **at the moment of binfmt_misc registration** from the host mount namespace.
- The kernel retains an internal `vfs` file descriptor to the interpreter binary.
- When an `x86_64` ELF is subsequently executed inside *any* container, chroot, or NsJail private mount namespace, the kernel executes the open file descriptor directly without looking for `/usr/bin/qemu-x86_64-static` inside the new rootfs.

Verification on `ubuntu` host:
```bash
cat /proc/sys/fs/binfmt_misc/qemu-x86_64
# Must output:
# enabled
# interpreter /usr/bin/qemu-x86_64-static
# flags: F
```

#### Containerized `linux/amd64` Execution via Podman / Docker
By executing the build within a `linux/amd64` container (e.g. `dhi.io/debian-base:bookworm-amd64` or `ubuntu:24.04-amd64` via Podman with `--arch amd64`):
- All host tools, shared libraries (`/lib64/ld-linux-x86-64.so.2`, `libc.so.6`), and AOSP prebuilts operate in an architecturally consistent x86_64 userland.
- `uname -m` inside the container naturally returns `x86_64`.
- The host ARM64 kernel handles instructions via `qemu-x86_64-static`.

#### Box64 vs QEMU User Static
- **QEMU User Static**: 100% full CPU emulation and accurate Linux syscall emulation. Essential for compilers, linkers, Go runtimes, and JIT engines that execute unconventional machine instructions or expect exact memory paging.
- **Box64**: Highly optimized dynarec with native library wrapping. While 3x–5x faster for games and pure compute, Box64 does not wrap complex internal AOSP toolchain libraries and can experience instabilities with NsJail user namespaces and multi-threaded Go runtimes in `soong_ui`. **Recommendation**: Standardize on `qemu-x86_64-static` with `flags: F`.

### 2.3 Execution Architecture B: Native ARM64 Prebuilts & `setarch x86_64` Personality

An alternative/hybrid approach is running natively on the ARM64 host and redirecting toolchains or fooling host architecture checks.

#### The `setarch x86_64` (or `linux64`) Personality Trick
When running directly on the `aarch64` host shell, running:
```bash
setarch x86_64 /bin/bash
```
changes the execution domain (`personality(PER_LINUX32/PER_LINUX)`) so that subsequent system calls to `uname(2)` report `x86_64` instead of `aarch64`.
- **Effect**: `build/envsetup.sh` and `soong_ui.bash` read `UNAME=x86_64` and select `linux-x86` prebuilts rather than erroring out on `aarch64`.
- **Requirement**: This still requires `qemu-x86_64-static` with the `F` flag enabled in `binfmt_misc`, because the binaries invoked under `prebuilts/` are still x86_64 ELFs.

#### Native ARM64 Prebuilts Status in AOSP/GrapheneOS
- Google's Android platform is gradually migrating internal tools to support `linux-arm64` hosts (particularly driven by internal Google Cloud ARM64 build instances and Apple Silicon developers).
- Modern AOSP trees contain limited `linux-arm64` prebuilts (e.g., Bazel / Kleaf kernel build tools, Chromium GN/Ninja).
- However, full GrapheneOS 17 builds still rely on `prebuilts/clang/host/linux-x86` and `prebuilts/build-tools/linux-x86` for Soong orchestration, Kati, and DEX/ART compilers (`dx`, `d8`, `r8`).
- **Complementary Hybrid Pattern**: Run Soong inside an `x86_64` personality/container with `qemu-user-static` (ensuring 100% build compatibility), while passing native ARM64 host utilities (like native `repo`, `git`, and system `ninja` where permitted) to minimize CPU emulation overhead.

---

## 3. `/mnt/extended` Directory Architecture & Concrete Storage Budget

The build host `ubuntu` has ~67 GB free on `/`. A single GrapheneOS checkout and build consumes between **250 GiB and 400 GiB**. Therefore, **all checkout trees, out directories, cache stores, vendor caches, and release packages must reside strictly on `/mnt/extended`**.

### 3.1 Concrete Disk Budget for GrapheneOS 17

| Component | Lightweight / Shallow Sync | Full Sync with Git History | Description / Mount Rule |
| :--- | :--- | :--- | :--- |
| **`.repo` + Source Checkout** | **90 GiB** (`--depth=1 -c`) | **136 – 160 GiB** | GrapheneOS platform manifest, Android 17 framework, external libraries. |
| **AOSP Build Output (`out/`)** | **100 – 140 GiB** | **140 – 180 GiB** | Intermediate objects, target libraries, target files package, system/vendor/product images. |
| **Compiler Cache (`ccache/`)** | **50 GiB** | **50 GiB** | Optional C/C++ compilation cache to dramatically speed up rebuilds. |
| **Release Artifacts (`releases/`)** | **20 GiB** | **20 GiB** | Signed factory images, OTA update zips, target files packages. |
| **Vendor Cache (`vendor_cache/`)**| **15 GiB** | **15 GiB** | Downloaded Pixel factory images, OTA zip payloads, adevtool unpack buffers. |
| **Temporary / Working Buffers** | **10 GiB** | **15 GiB** | Tool unpacks, oat dumps, apksigner temp files. |
| **TOTAL DISK ALLOCATION** | **~285 GiB** | **~440 GiB** | Must fit comfortably within `/mnt/extended`. |

### 3.2 `/mnt/extended` Directory Layout

```
/mnt/extended/
├── grapheneos/
│   ├── workspace/                      # Root AOSP source checkout
│   │   ├── .repo/                      # Repo manifest and git object stores
│   │   ├── build/
│   │   ├── vendor/adevtool/
│   │   ├── out -> /mnt/extended/grapheneos/out # Symlink or direct bind mount
│   │   └── ...
│   ├── out/                            # High-churn build outputs
│   ├── ccache/                         # Persistent ccache directory (CCACHE_DIR)
│   ├── vendor_cache/                   # Pixel factory images for adevtool (ADEVTOOL_CACHE_DIR)
│   ├── releases/                       # Final signed releases and update zips
│   └── container_home/                 # Home directory when building inside container
```

To configure:
```bash
sudo mkdir -p /mnt/extended/grapheneos/{workspace,out,ccache,vendor_cache,releases,container_home}
sudo chown -R $USER:$USER /mnt/extended/grapheneos
```

### 3.3 Ephemeral `tmpfs` RAM Disk for Release Signing Keys
**Security Invariant:** Decrypted cryptographic private keys (RSA 4096 AVB keys, release keys, platform keys, Ed25519 factory image keys) **must never touch persistent NVMe storage blocks** on `/mnt/extended` or `/`, and must be guarded against being swapped to disk.

GrapheneOS provides `script/decrypt-keys` and `script/encrypt-keys`. During production signing:
1. Keys are stored encrypted with AES-256 (scrypt KDF) in git or secure vault.
2. A dedicated, non-swappable `tmpfs` ramdisk is mounted:
   ```bash
   sudo mkdir -p /mnt/ramdisk/keys
   sudo mount -t tmpfs -o size=256M,mode=0700,noexec,nosuid,nodev tmpfs /mnt/ramdisk/keys
   ```
3. Decrypted keys are placed into `/mnt/ramdisk/keys`.
4. Build scripts reference `KEYS_DIR=/mnt/ramdisk/keys`.
5. Upon signing completion, the ramdisk is unmounted and zeroed:
   ```bash
   sudo umount /mnt/ramdisk/keys
   ```
6. **Swap Hardening**: Swap must be either disabled (`sudo swapoff -a`) during signing or backed by an ephemeral randomly-keyed swap device (`dm-crypt` with `/dev/urandom` key) to guarantee zero persistent key leakage.

---

## 4. Hardware I/O Protection & Concurrency Tuning for `ubuntu`

### 4.1 The Hardware Fault Mode
The Microsoft Surface Laptop 7 Snapdragon X Elite platform under high concurrent write IOPS (such as Git checking out 800+ repositories simultaneously or Ninja linking hundreds of shared objects) experiences storage controller stalls that can cause the runner to hang or kernel panic.

### 4.2 Throttled Execution Discipline
All heavy CI steps must be wrapped with scheduling priorities and strict concurrency boundaries:

1. **Scheduling Class Wrapper**:
   - `nice -n 19`: Lowest CPU scheduling priority for background compilation.
   - `ionice -c3`: Idle I/O scheduling class (processes only get disk time when no other program is accessing storage).
   ```bash
   THROTTLE="nice -n 19 ionice -c3"
   ```

2. **Repository Synchronization**:
   ```bash
   # DO NOT run repo sync -j16 or -j32
   $THROTTLE repo sync -c --no-clone-bundle --no-tags -j4
   ```
   - `-c`: Current branch only (saves ~45 GiB of storage).
   - `--no-clone-bundle`: Avoids downloading massive git bundles through Python memory buffers.
   - `-j4`: Restricts concurrent network and disk write streams to 4.

3. **Ninja / Soong Build**:
   ```bash
   # Bounded Ninja concurrency
   export NINJA_ARGS="-j8 -l10"
   $THROTTLE m -j8 -l10 target-files-package otatools-package
   ```
   - `-j8`: Limits compilation jobs to 8 concurrent threads (leaving 4 of the 12 Oryon cores free for kernel I/O flushers and system responsiveness).
   - `-l10`: Load average throttle (Ninja will not spawn new jobs if system 1-minute load exceeds 10.0).

---

## 5. Verification Checklist & Concrete CI Action Plan

Before executing the first GrapheneOS build run on `ubuntu`, verify the host against these gates:

- [ ] **Binfmt Verification**: `/proc/sys/fs/binfmt_misc/qemu-x86_64` has `flags: F`.
- [ ] **x86_64 Emulation Smoke Test**: Run `qemu-x86_64-static /bin/true` or test an x86_64 binary in the container.
- [ ] **Filesystem Mount**: `/mnt/extended` is mounted with `rw,exec` and ownership assigned to the runner user.
- [ ] **Node.js Environment**: `node -v` reports `v24.x.x` and `corepack enable` is verified.
- [ ] **I/O Throttling Active**: CI workflows explicitly prepend `nice -n 19 ionice -c3` and clamp `repo sync -j4` and `ninja -j8 -l10`.
- [ ] **Signing tmpfs Configured**: RAM disk mount script ready for staging release keys without NVMe writes.
