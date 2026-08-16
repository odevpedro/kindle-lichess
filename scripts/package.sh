#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_source="${repo_dir}/plugin/kindlelichess.koplugin"
binary="${repo_dir}/dist/armv7/kindle-lichess-bridge"
dist_dir="${repo_dir}/dist"
stage_root="${dist_dir}/package-stage"
package_root="${stage_root}/kindlelichess.koplugin"
archive="${dist_dir}/kindlelichess-koplugin-armv7.tar.gz"
source_date_epoch="${SOURCE_DATE_EPOCH:-0}"

if [[ ! "${source_date_epoch}" =~ ^[0-9]+$ ]]; then
    echo "erro: SOURCE_DATE_EPOCH deve ser inteiro não negativo" >&2
    exit 2
fi
if [[ ! -x "${binary}" ]]; then
    echo "erro: execute ./scripts/build-armv7.sh primeiro" >&2
    exit 2
fi
for dependency in find gzip install sha256sum sort tar; do
    if ! command -v "${dependency}" >/dev/null 2>&1; then
        echo "erro: dependência ausente: ${dependency}" >&2
        exit 2
    fi
done

case "${stage_root}" in
    "${repo_dir}/dist/package-stage") rm -rf -- "${stage_root}" ;;
    *) echo "erro: staging inseguro" >&2; exit 2 ;;
esac
mkdir -p "${package_root}/bin"

install -m 0644 "${plugin_source}/_meta.lua" "${package_root}/_meta.lua"
install -m 0644 "${plugin_source}/main.lua" "${package_root}/main.lua"
install -m 0644 "${plugin_source}/controller.lua" "${package_root}/controller.lua"
install -m 0644 "${plugin_source}/i18n.lua" "${package_root}/i18n.lua"
for directory in bridge chess icons storage ui; do
    cp -a "${plugin_source}/${directory}" "${package_root}/${directory}"
done
install -m 0755 "${binary}" "${package_root}/bin/kindle-lichess-bridge"
install -m 0644 "${repo_dir}/LICENSE" "${package_root}/LICENSE"
install -m 0644 "${repo_dir}/NOTICE" "${package_root}/NOTICE"
install -m 0644 "${repo_dir}/token.example" "${package_root}/token.example"

find "${package_root}" -type d -exec chmod 0755 {} +
find "${package_root}" -type f ! -path '*/bin/kindle-lichess-bridge' -exec chmod 0644 {} +

(
    cd "${package_root}"
    find . -type f ! -name MANIFEST.sha256 -print0 \
        | sort -z \
        | xargs -0 sha256sum
) >"${package_root}/MANIFEST.sha256"
chmod 0644 "${package_root}/MANIFEST.sha256"

tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner \
    --mtime="@${source_date_epoch}" -cf - -C "${stage_root}" kindlelichess.koplugin \
    | gzip -n >"${archive}"

tar -tzf "${archive}"
sha256sum "${archive}"
