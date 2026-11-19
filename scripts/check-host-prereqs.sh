#!/usr/bin/env bash
set -euo pipefail

EXTENDED_ROOT="${EXTENDED_ROOT:-/mnt/extended/grapheneos}"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"
mkdir -p "$EVIDENCE_DIR"

echo "=== [1/6] Host Load & Top CPU Processes Check (Mandatory Preflight) ==="
{
  echo "Timestamp: $(date -u +%FT%TZ)"
  echo "Uptime: $(uptime)"
  echo "--- Top 15 CPU Processes ---"
  ps -eo pid,user,pcpu,pmem,stat,comm,args --sort=-pcpu | head -n 16
} | tee "$EVIDENCE_DIR/host-load.txt"

echo "=== [2/6] System Architecture, Memory & Swap Inspection ==="
{
  uname -a
  cat /etc/os-release
  echo "Logical CPUs: $(nproc)"
  free -h
  cat /proc/swaps || true
} | tee "$EVIDENCE_DIR/host-system.txt"

echo "=== [3/6] Storage & /mnt/extended Capacity Verification ==="
if [ ! -d "/mnt/extended" ]; then
  echo "ERROR: /mnt/extended does not exist on this host!" >&2
  exit 1
fi
mkdir -p "$EXTENDED_ROOT"/{bin,x86_64-shim,.ssh,manifest-check,workspace,out,ccache,vendor_cache,kernels,vanadium,sdk,releases}
cat > "$EXTENDED_ROOT/x86_64-shim/uname" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-m" ] || [ "${1:-}" = "-p" ] || [ "${1:-}" = "-i" ]; then
  echo x86_64
else
  /usr/bin/uname "$@" | sed "s/aarch64/x86_64/g"
fi
EOF
chmod 0755 "$EXTENDED_ROOT/x86_64-shim/uname"
{
  df -h / /mnt/extended "$GITHUB_WORKSPACE"
  df -B1G /mnt/extended
  stat -c "%A %U:%G %n" /mnt/extended "$EXTENDED_ROOT"
} | tee "$EVIDENCE_DIR/storage-layout.txt"

echo "=== [4/6] GrapheneOS Host Prerequisite Binary Audit ==="
MISSING=0
{
  for cmd in git python3 gpg ssh-keygen openssl rsync zip unzip diff hostname fc-list bc bison flex gperf zstd mke2fs mksquashfs cpio sha256sum sha512sum nice ionice; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf "OK      %-16s -> %s\n" "$cmd" "$(command -v "$cmd")"
    else
      printf "MISSING %-16s\n" "$cmd"
      MISSING=$((MISSING + 1))
    fi
  done
  for opt_cmd in repo node yarn corepack qemu-x86_64 git-lfs lz4 podman docker pkcs11-tool fido2-assert; do
    if command -v "$opt_cmd" >/dev/null 2>&1; then
      printf "OPT_OK  %-16s -> %s\n" "$opt_cmd" "$(command -v "$opt_cmd")"
    else
      printf "OPT_ABS %-16s (bootstrapped on /mnt/extended or host apt)\n" "$opt_cmd"
    fi
  done
} | tee "$EVIDENCE_DIR/prereq-binaries.txt"

echo "=== [5/6] ARM64-to-x86_64 Emulation & binfmt_misc Verification ==="
{
  echo "Native host arch: $(/usr/bin/uname -m)"
  echo "Shimmed AOSP host arch: $(PATH="$EXTENDED_ROOT/x86_64-shim:$PATH" uname -m)"
  test "$(PATH="$EXTENDED_ROOT/x86_64-shim:$PATH" uname -m)" = "x86_64"
  test -f /proc/sys/fs/binfmt_misc/qemu-x86_64
  echo "--- /proc/sys/fs/binfmt_misc/qemu-x86_64 ---"
  cat /proc/sys/fs/binfmt_misc/qemu-x86_64
  grep -q 'enabled' /proc/sys/fs/binfmt_misc/qemu-x86_64
  grep -E -q 'flags:.*F' /proc/sys/fs/binfmt_misc/qemu-x86_64
  echo "PASS: binfmt_misc qemu-x86_64 is enabled with F (fix-binary) flag for Soong nsjail sandboxes."
} | tee "$EVIDENCE_DIR/binfmt-status.txt"

echo "=== [6/6] PINNED.md Supply-Chain Integrity Check ==="
{
  test -f PINNED.md
  grep -q '05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a' PINNED.md
  grep -q '344f59c6f058699e63fea68e35953b341c14e3bf1fbc1256f6baa84aa2aca1d0' PINNED.md
  grep -q 'c2f57432b89dda12ec40f07768d3c3a75bde9634' PINNED.md
  grep -q 'e5681d7438f52a75819d1f34f8d738fcaa54654c' PINNED.md
  echo "PINNED.md verified: all core GrapheneOS 2026111800 and tool digests present."
} | tee "$EVIDENCE_DIR/pinned-audit.txt"
