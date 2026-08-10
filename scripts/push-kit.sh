#!/usr/bin/env bash
# push-kit.sh — validate and push one of this repo's kits to an OCI registry as
# a self-contained artifact (spec.yaml + files/ + README + LICENSE).
#
#   ./scripts/push-kit.sh                    # push kit/ as :latest to ghcr.io/dirien/infrastructure-kit
#   TAG=v0.8.0 ./scripts/push-kit.sh         # push a specific tag
#   KIT_DIR=sandbox-kit KIT_NAME=infrastructure-sandbox-kit ./scripts/push-kit.sh
#   REGISTRY=ghcr.io/you ./scripts/push-kit.sh
#
# Requires `sbx` and Docker logged in to the registry (the CI workflow handles both).
# Consumers run it by a bare OCI reference (no oci:// prefix); a tag works, a digest
# pins it exactly:
#   sbx run --kit ghcr.io/dirien/infrastructure-kit:latest claude .   # mixin
#   sbx run --kit ghcr.io/dirien/infrastructure-sandbox-kit:latest infrastructure-sandbox .
#
# Reproducibility: the staged spec.yaml's KIT_REF is rewritten to the exact commit
# SHA being published, so a pinned OCI artifact always fetches its provisioning
# scripts from an immutable commit (never a moving branch).
set -euo pipefail

registry="${REGISTRY:-ghcr.io/dirien}"
kit_dir="${KIT_DIR:-kit}"
name="${KIT_NAME:-infrastructure-kit}"
tag="${TAG:-latest}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${registry}/${name}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
dest="$stage/$name"
mkdir -p "$dest"

# Stage the kit: spec.yaml + its README + the files/ tree, plus the repo LICENSE.
cp -a "$repo_root/$kit_dir/." "$dest/"
[ -f "$repo_root/LICENSE" ] && cp -f "$repo_root/LICENSE" "$dest/LICENSE"

# The sandbox kit shares the mixin's static files/ tree (runbooks); stage it in
# so both artifacts ship identical home content.
if [ "$kit_dir" != "kit" ] && [ ! -d "$dest/files" ] && [ -d "$repo_root/kit/files" ]; then
  cp -a "$repo_root/kit/files" "$dest/files"
fi

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
