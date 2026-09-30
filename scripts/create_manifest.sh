#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# shellcheck disable=SC2034  # Used by workflows that source this helper.
read -ra cuda_versions <<< "${MANIFEST_CUDA_VERSION:-12.9 13.1}"
manifest_base_tags=()
create_manifest_alias() {
  local tag="$1"
  local final_tag="$2"
  local attempts=${MANIFEST_CREATE_ATTEMPTS:-5}
  local delay=${MANIFEST_CREATE_BACKOFF_INITIAL:-5}

  local architectures
  read -ra architectures <<< "${MANIFEST_ARCHITECTURE:-amd64 arm64}"

  local sources=()
  local arch
  for arch in "${architectures[@]}"; do
    sources+=("${REGISTRY}/${IMAGE_NAME}:${tag}-${BUILD_VARIANT}-${GITHUB_RUN_ID}-${arch}")
  done

  echo "Creating multi-arch manifest: ${final_tag}"
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if docker buildx imagetools create \
      -t "${REGISTRY}/${IMAGE_NAME}:${final_tag}" "${sources[@]}"; then
      return 0
    fi
    if (( attempt < attempts )); then
      echo "Manifest creation failed (attempt ${attempt}/${attempts}); retrying in ${delay}s..." >&2
      sleep "${delay}"
      delay=$((delay * 2))
    fi
  done
  echo "Manifest creation failed after ${attempts} attempts." >&2
  return 1
}

resolve_run_id_suffix() {
  if [[ -z "${GITHUB_RUN_ID:-}" ]]; then
    echo "GITHUB_RUN_ID must be set" >&2
    return 1
  fi
  if [[ "${BUILD_VARIANT:-}" != "nightly" && -n "${BUILD_VARIANT:-}" ]]; then
    printf -- '-%s-%s' "${BUILD_VARIANT}" "${GITHUB_RUN_ID}"
  fi
}

create_manifest() {
  local tag="$1"

  create_manifest_alias "${tag}" "${tag}$(resolve_run_id_suffix)"
  manifest_base_tags+=("${tag}-${BUILD_VARIANT}-${GITHUB_RUN_ID}")
}

write_manifest_base_tags() {
  {
    echo 'base_tags<<EOF'
    printf '%s\n' "${manifest_base_tags[@]}"
    echo 'EOF'
  } >> "${GITHUB_OUTPUT}"
}
