#!/usr/bin/env bash
# push-kit.sh — validate and push the infrastructure kit to an OCI registry as a
# self-contained artifact (spec.yaml + files/ + README + LICENSE).
#
#   ./scripts/push-kit.sh                    # push :latest to ghcr.io/dirien/infrastructure-kit
#   TAG=v0.6.0 ./scripts/push-kit.sh         # push a specific tag
#   REGISTRY=ghcr.io/you ./scripts/push-kit.sh
#
# Requires `sbx` and Docker logged in to the registry (the CI workflow handles both).
# Consumers run it by a bare OCI reference (no oci:// prefix); a tag works, a digest
# pins it exactly:
#   sbx run --kit ghcr.io/dirien/infrastructure-kit:latest claude .
#   sbx run --kit ghcr.io/dirien/infrastructure-kit@sha256:<digest> claude .
#
# Reproducibility: the staged spec.yaml's KIT_REF is rewritten to the exact commit
# SHA being published, so a pinned OCI artifact always fetches its provisioning
# scripts from an immutable commit (never a moving branch).
set -euo pipefail

registry="${REGISTRY:-ghcr.io/dirien}"
name="${KIT_NAME:-infrastructure-kit}"
tag="${TAG:-latest}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${registry}/${name}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
dest="$stage/$name"
mkdir -p "$dest"

# Stage the kit: spec.yaml + its README + the files/ tree, plus the repo LICENSE.
cp -a "$repo_root/kit/." "$dest/"
[ -f "$repo_root/LICENSE" ] && cp -f "$repo_root/LICENSE" "$dest/LICENSE"

# Pin KIT_REF to the exact commit SHA so the published artifact is reproducible.
sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
if [ -n "$sha" ]; then
  perl -0pi -e 's/(KIT_REF=")[^"]*(")/${1}'"$sha"'${2}/' "$dest/spec.yaml"
  echo "pinned KIT_REF=${sha} in the published spec.yaml"
else
  echo "WARNING: not a git checkout — publishing with KIT_REF unchanged" >&2
fi

sbx kit validate "$dest"
sbx kit push "$dest" "${image}:${tag}"
echo "pushed ${image}:${tag}"
