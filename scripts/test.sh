#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pedro Schmidt

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unit_test="plugin/kindlelichess.koplugin/tests/run_unit.lua"

cd "${repo_dir}"

if command -v luajit >/dev/null 2>&1; then
    luajit "${unit_test}"
elif command -v lua >/dev/null 2>&1; then
    lua "${unit_test}"
elif command -v nvim >/dev/null 2>&1; then
    nvim --headless -u NONE \
        -c "lua local ok,err=pcall(dofile,'${unit_test}'); if not ok then print(err); vim.cmd('cquit 1') end" \
        -c "qa!"
else
    echo "erro: LuaJIT, Lua ou Neovim com Lua são necessários para os testes unitários" >&2
    exit 1
fi
echo

if [[ -z "${KOREADER_SOURCE:-}" ]]; then
    echo "KOReader: teste de integração ignorado (defina KOREADER_SOURCE para uma árvore desktop já compilada)"
    exit 0
fi

if [[ "${KOREADER_SOURCE}" != /* || ! -f "${KOREADER_SOURCE}/kodev" ]]; then
    echo "erro: KOREADER_SOURCE deve ser o caminho absoluto de uma árvore KOReader válida" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "erro: Docker é necessário para executar o runtime oficial do KOReader" >&2
    exit 1
fi

koreader_image="koreader/koappimage@sha256:4416f7b137b1eda49eb486bbe00dd00a347f0f126a649bf75bf1edc8d4877828"

docker run --rm --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e GIT_CONFIG_COUNT=1 \
    -e GIT_CONFIG_KEY_0=safe.directory \
    -e GIT_CONFIG_VALUE_0=/work \
    -v "${KOREADER_SOURCE}:/work" \
    -v "${repo_dir}/plugin/kindlelichess.koplugin:/work/plugins/kindlelichess.koplugin:ro" \
    -w /work \
    "${koreader_image}" \
    bash -lc './kodev test -b --busted front plugins/kindlelichess.koplugin/tests/koreader_spec.lua'
