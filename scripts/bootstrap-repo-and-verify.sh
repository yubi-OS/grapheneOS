#!/usr/bin/env bash
set -euo pipefail

EXTENDED_ROOT="${EXTENDED_ROOT:-/mnt/extended/grapheneos}"
MANIFEST_TAG="${MANIFEST_TAG:-2026111800}"
EXPECTED_TAG_OBJ="e5681d7438f52a75819d1f34f8d738fcaa54654c"
EXPECTED_COMMIT_SHA="c2f57432b89dda12ec40f07768d3c3a75bde9634"
REPO_SHA256="05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a"
REPO_SHA512="710d15d09903655d4df5b4f2562f0a1257dd5e0da3ed723e92853b8fe4228a1aaccf978d7044c56f23e40db9ba26ec1460072f41062aa31b0e713d31e586970b"
SIGNERS_SHA256="344f59c6f058699e63fea68e35953b341c14e3bf1fbc1256f6baa84aa2aca1d0"
SIGNERS_SHA512="af6ae0ca380a83da7b3e3cca0aa4d28f91554628610c869fa159f6ea5c4cda07138c4c621117088a63463d0cec20196ff81a08a7d6d16c19402b5c1fd3cff590"
GITLFS_SHA256="73a9c90eeb4312133a63c3eaee0c38c019ea7bfa0953d174809d25b18588dd8d"
GITLFS_SHA512="858ff2c5bec3b278acba3b6fe19b229d7786c723b177408a111953c367c2f93693108bdd445aa6702d88e31ad857adf91284afb75ed5be5bec1a23472d19de55"
NODE_VER="v24.22.3"
NODE_TAR="node-${NODE_VER}-linux-arm64.tar.xz"
NODE_SHA256="6e51a2ada00f0011cc266f65d98922b403d7ad88f809ca2aa615a5fe1ce6e86c"
NODE_SHA512="69acc8f30bb09dcc2882ea495bc1b01f74471b17d3aebbe796fa583618c89fb193218e6f7b07123ef60a9308a64c0963641fb85636b2235e1b8dae2b9d3c3ac8"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"

mkdir -p "$EXTENDED_ROOT/bin" "$EXTENDED_ROOT/.ssh" "$EXTENDED_ROOT/manifest-check" "$EXTENDED_ROOT/vendor_cache/yarn" "$EVIDENCE_DIR"

echo "=== [1/4] Downloading & SHA-256/SHA-512 Verifying Google repo Launcher ==="
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$EXTENDED_ROOT/bin/repo"
echo "${REPO_SHA256}  $EXTENDED_ROOT/bin/repo" | sha256sum --check --strict
echo "${REPO_SHA512}  $EXTENDED_ROOT/bin/repo" | sha512sum --check --strict
chmod 0755 "$EXTENDED_ROOT/bin/repo"

echo "=== [2/4] Bootstrapping & Verifying git-lfs v3.7.1 + Node.js v24.22.3 + Yarn on /mnt/extended ==="
if [ ! -x "$EXTENDED_ROOT/bin/git-lfs" ]; then
  curl -fsSL https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-linux-arm64-v3.7.1.tar.gz -o "$EXTENDED_ROOT/bin/git-lfs.tar.gz"
  echo "${GITLFS_SHA256}  $EXTENDED_ROOT/bin/git-lfs.tar.gz" | sha256sum --check --strict
  echo "${GITLFS_SHA512}  $EXTENDED_ROOT/bin/git-lfs.tar.gz" | sha512sum --check --strict
  tar -xzf "$EXTENDED_ROOT/bin/git-lfs.tar.gz" -C "$EXTENDED_ROOT/bin" --strip-components=1 git-lfs-3.7.1/git-lfs
  chmod 0755 "$EXTENDED_ROOT/bin/git-lfs"
  rm -f "$EXTENDED_ROOT/bin/git-lfs.tar.gz"
fi
if [ ! -x "$EXTENDED_ROOT/bin/node-${NODE_VER}/bin/node" ]; then
  curl -fsSL "https://nodejs.org/dist/${NODE_VER}/${NODE_TAR}" -o "$EXTENDED_ROOT/bin/${NODE_TAR}"
  echo "${NODE_SHA256}  $EXTENDED_ROOT/bin/${NODE_TAR}" | sha256sum --check --strict
  echo "${NODE_SHA512}  $EXTENDED_ROOT/bin/${NODE_TAR}" | sha512sum --check --strict
  mkdir -p "$EXTENDED_ROOT/bin/node-${NODE_VER}"
  tar -xJf "$EXTENDED_ROOT/bin/${NODE_TAR}" --strip-components=1 -C "$EXTENDED_ROOT/bin/node-${NODE_VER}"
  rm -f "$EXTENDED_ROOT/bin/${NODE_TAR}"
fi
ln -sf "$EXTENDED_ROOT/bin/node-${NODE_VER}/bin/node" "$EXTENDED_ROOT/bin/node"
ln -sf "$EXTENDED_ROOT/bin/node-${NODE_VER}/bin/corepack" "$EXTENDED_ROOT/bin/corepack"
"$EXTENDED_ROOT/bin/node-${NODE_VER}/bin/corepack" enable --install-directory "$EXTENDED_ROOT/bin"

echo "=== [3/4] Downloading & SHA-256/SHA-512 Verifying GrapheneOS allowed_signers ==="
curl -fsSL https://grapheneos.org/allowed_signers -o "$EXTENDED_ROOT/.ssh/grapheneos_allowed_signers"
echo "${SIGNERS_SHA256}  $EXTENDED_ROOT/.ssh/grapheneos_allowed_signers" | sha256sum --check --strict
echo "${SIGNERS_SHA512}  $EXTENDED_ROOT/.ssh/grapheneos_allowed_signers" | sha512sum --check --strict
chmod 0644 "$EXTENDED_ROOT/.ssh/grapheneos_allowed_signers"

echo "=== [4/4] Cloning & Cryptographically Verifying GrapheneOS/platform_manifest @ ${MANIFEST_TAG} ==="
MANIFEST_DIR="$EXTENDED_ROOT/manifest-check/platform_manifest"
if [ ! -d "$MANIFEST_DIR/.git" ]; then
  git clone --no-checkout https://github.com/GrapheneOS/platform_manifest.git "$MANIFEST_DIR"
fi
git -C "$MANIFEST_DIR" fetch --tags --force origin "refs/tags/${MANIFEST_TAG}:refs/tags/${MANIFEST_TAG}"
git -C "$MANIFEST_DIR" config gpg.ssh.allowedSignersFile "$EXTENDED_ROOT/.ssh/grapheneos_allowed_signers"

{
  echo "Verifying OpenSSH Ed25519 signature on tag ${MANIFEST_TAG}..."
  git -C "$MANIFEST_DIR" verify-tag "${MANIFEST_TAG}" 2>&1
  TAG_OBJ=$(git -C "$MANIFEST_DIR" rev-parse "refs/tags/${MANIFEST_TAG}")
  COMMIT_SHA=$(git -C "$MANIFEST_DIR" rev-parse "refs/tags/${MANIFEST_TAG}^{commit}")
  echo "Resolved tag object SHA: $TAG_OBJ"
  echo "Resolved peeled commit SHA: $COMMIT_SHA"
  if [ "${MANIFEST_TAG}" = "2026111800" ]; then
    test "$TAG_OBJ" = "$EXPECTED_TAG_OBJ"
    test "$COMMIT_SHA" = "$EXPECTED_COMMIT_SHA"
    echo "PASS: Tag object and peeled commit match PINNED.md exactly."
  fi
  git -C "$MANIFEST_DIR" checkout --detach "$COMMIT_SHA"
  PROJECT_COUNT=$(grep -c "<project " "$MANIFEST_DIR/default.xml")
  GOS_FORK_COUNT=$(grep -c 'remote="grapheneos' "$MANIFEST_DIR/default.xml")
  echo "Manifest default.xml verified: ${PROJECT_COUNT} total projects (${GOS_FORK_COUNT} GrapheneOS forks)."
  echo "Tool versions in /mnt/extended/grapheneos/bin:"
  "$EXTENDED_ROOT/bin/git-lfs" --version
  "$EXTENDED_ROOT/bin/node" --version
  "$EXTENDED_ROOT/bin/yarn" --version
} | tee "$EVIDENCE_DIR/manifest-verification.txt"
