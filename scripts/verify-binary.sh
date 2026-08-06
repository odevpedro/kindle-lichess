#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${1:-${repo_dir}/dist/armv7/kindle-lichess-bridge}"

if [[ "${binary}" != /* || ! -f "${binary}" || -L "${binary}" ]]; then
    echo "erro: binário deve ser um arquivo absoluto, regular e não simbólico" >&2
    exit 2
fi
for dependency in file readelf sha256sum; do
    if ! command -v "${dependency}" >/dev/null 2>&1; then
        echo "erro: dependência ausente: ${dependency}" >&2
        exit 2
    fi
done

description="$(file -b "${binary}")"
header="$(readelf -hW "${binary}")"
program_headers="$(readelf -lW "${binary}")"
dynamic="$(readelf -dW "${binary}" 2>&1 || true)"

[[ "${description}" == *"ELF 32-bit LSB executable"* ]] \
    || { echo "erro: classe ELF inesperada" >&2; exit 1; }
[[ "${description}" == *"ARM"* ]] \
    || { echo "erro: arquitetura não é ARM" >&2; exit 1; }
[[ "${description}" == *"statically linked"* ]] \
    || { echo "erro: binário não é estático" >&2; exit 1; }
[[ "${header}" == *"Machine:"*"ARM"* ]] \
    || { echo "erro: e_machine não é ARM" >&2; exit 1; }
[[ "${header}" == *"Version5 EABI"* ]] \
    || { echo "erro: EABI5 não confirmado" >&2; exit 1; }
[[ "${program_headers}" != *"INTERP"* ]] \
    || { echo "erro: interpretador dinâmico inesperado" >&2; exit 1; }
[[ "${dynamic}" == *"There is no dynamic section"* ]] \
    || { echo "erro: seção dinâmica inesperada" >&2; exit 1; }

printf '%s\n' "${description}"
printf '%s\n' "${header}" | sed -n '/Class:/p;/Data:/p;/Type:/p;/Machine:/p;/Flags:/p'
printf '%s\n' "sem PT_INTERP; sem seção dinâmica"
sha256sum "${binary}"
