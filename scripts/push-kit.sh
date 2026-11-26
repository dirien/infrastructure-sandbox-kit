#!/usr/bin/env bash
# push-kit.sh — publish one of this repo's kits to an OCI registry.
#
#   ./scripts/push-kit.sh                    # push kit/ as :latest to ghcr.io/dirien/infrastructure-kit
#   TAG=v0.10.9 ./scripts/push-kit.sh         # push a specific tag
#   KIT_DIR=sandbox-kit KIT_NAME=infrastructure-sandbox-kit ./scripts/push-kit.sh
#   REGISTRY=ghcr.io/you ./scripts/push-kit.sh
#
# The two kits use different spec versions, so they publish differently:
#   * kit/ is a kit-spec v3 mixin (a `# syntax=docker/sandbox-kit:3` descriptor
#     plus its companion Dockerfile). It is an OCI image built by the
#     docker/sandbox-kit:3 BuildKit frontend, which also validates it, and pushed
#     multi-arch with `docker buildx build --push`. Use a docker-container builder
#     (BUILDER=<name>, or docker/setup-buildx-action in CI): the classic docker
#     driver can drop the descriptor annotations.
#   * sandbox-kit/ is a kit-spec v2 `kind: sandbox` kit: `sbx kit validate
#     --offline` then `sbx kit push` (spec.yaml + files/ + README + LICENSE).
#
# Requires Docker logged in to the registry (and `sbx` for the v2 kit); the CI
# workflow handles both. Consumers run a kit by a bare OCI reference:
#   sbx run claude --kit ghcr.io/dirien/infrastructure-kit:latest .        # v3 mixin
#   sbx run ghcr.io/dirien/infrastructure-sandbox-kit:latest .              # v2 sandbox kit
#
# Reproducibility: the staged descriptor's KIT_REF is rewritten to the exact
# commit SHA being published, so a pinned OCI artifact always fetches its
# provisioning scripts from an immutable commit (never a moving branch).
set -euo pipefail

registry="${REGISTRY:-ghcr.io/dirien}"
kit_dir="${KIT_DIR:-kit}"
name="${KIT_NAME:-infrastructure-kit}"
tag="${TAG:-latest}"
platforms="${PLATFORMS:-linux/amd64,linux/arm64}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="${registry}/${name}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
dest="$stage/$name"
mkdir -p "$dest"

cp -a "$repo_root/$kit_dir/." "$dest/"

# The v3 descriptor is the YAML file whose first line selects the v3 frontend;
# a v2 kit has a spec.yaml instead.
descriptor=""
for f in "$dest"/*.yaml; do
  [ -f "$f" ] || continue
  if head -n 1 "$f" | grep -q '^# syntax=docker/sandbox-kit:3'; then
    descriptor="$f"
    break
  fi
done
if [ -z "$descriptor" ]; then
  [ -f "$dest/spec.yaml" ] || { echo "no kit descriptor in $kit_dir" >&2; exit 1; }
  # v2: ship LICENSE and the mixin's static files/ tree (runbooks) so both kits
  # carry identical home content.
  [ -f "$repo_root/LICENSE" ] && cp -f "$repo_root/LICENSE" "$dest/LICENSE"
  if [ ! -d "$dest/files" ] && [ -d "$repo_root/kit/files" ]; then
    cp -a "$repo_root/kit/files" "$dest/files"
  fi
fi
spec="${descriptor:-$dest/spec.yaml}"

# Pin KIT_REF to the exact commit SHA so the published artifact is reproducible.
sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
if [ -n "$sha" ]; then
  perl -0pi -e 's/(KIT_REF=")[^"]*(")/${1}'"$sha"'${2}/' "$spec"
  echo "pinned KIT_REF=${sha} in the published $(basename "$spec")"
else
  echo "WARNING: not a git checkout — publishing with KIT_REF unchanged" >&2
fi

if [ -n "$descriptor" ]; then
  docker buildx build ${BUILDER:+--builder "$BUILDER"} "$dest" \
    -f "$descriptor" \
    --platform "$platforms" \
    --provenance=mode=min \
    --push -t "${image}:${tag}"
else
  sbx kit validate --offline "$dest"
  sbx kit push "$dest" "${image}:${tag}"
fi
echo "pushed ${image}:${tag}"
