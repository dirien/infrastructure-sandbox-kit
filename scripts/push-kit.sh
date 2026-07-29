#!/usr/bin/env bash
# push-kit.sh — validate and push the infrastructure kit to an OCI registry as a
# self-contained artifact (spec.yaml + files/ + README + LICENSE).
#
#   ./scripts/push-kit.sh                    # push :latest to ghcr.io/dirien/infrastructure-kit
#   TAG=v0.2.0 ./scripts/push-kit.sh         # push a specific tag
#   REGISTRY=ghcr.io/you ./scripts/push-kit.sh
#
# Requires `sbx` and Docker logged in to the registry (the CI workflow handles
# both). Consumers then run, pinned by digest (OCI refs must be digests):
#   sbx run --kit "oci://ghcr.io/dirien/infrastructure-kit@sha256:<digest>" claude .
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

sbx kit validate "$dest"
sbx kit push "$dest" "${image}:${tag}"
echo "pushed ${image}:${tag}"
