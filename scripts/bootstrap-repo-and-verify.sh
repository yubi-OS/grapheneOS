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
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"

mkdir -p "$EXTENDED_ROOT/bin" "$EXTENDED_ROOT/.ssh" "$EXTENDED_ROOT/manifest-check" "$EVIDENCE_DIR"

echo "=== [1/3] Downloading & SHA-256/SHA-512 Verifying Google repo Launcher ==="
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$EXTENDED_ROOT/bin/repo"
echo "${REPO_SHA256}  $EXTENDED_ROOT/bin/repo" | sha256sum --check --strict
echo "${REPO_SHA512}  $EXTENDED_ROOT/bin/repo" | sha512sum --check --strict
chmod 0755 "$EXTENDED_ROOT/bin/repo"

echo "=== [2/3] Downloading & SHA-256/SHA-512 Verifying GrapheneOS allowed_signers ==="
curl -fsSL https://grapheneos.org/allowed_signers -o "$EXTENDED_ROOT/.ssh/grapheneos_allowed_signers"
echo "${SIGNERS_SHA256}  $EXTENDED_ROOT/.ssh/grapheneos_allowed_signers" | sha256sum --check --strict
echo "${SIGNERS_SHA512}  $EXTENDED_ROOT/.ssh/grapheneos_allowed_signers" | sha512sum --check --strict
chmod 0644 "$EXTENDED_ROOT/.ssh/grapheneos_allowed_signers"

echo "=== [3/3] Cloning & Cryptographically Verifying GrapheneOS/platform_manifest @ ${MANIFEST_TAG} ==="
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
} | tee "$EVIDENCE_DIR/manifest-verification.txt"
