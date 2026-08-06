# Licenciamento e proveniência

Análise técnica, não parecer jurídico.

## Kochess

Texto GPLv3 e README “GPL 3.0 or above”, copyright Baptiste Fouques. Fork deve ser compatível com `GPL-3.0-or-later`, preservar LICENSE, avisos, créditos e ancestry Git. Peças creditadas a Colin M.L. Burnett sob GPLv2+ exigem inventário/avisos.

## Lacuna de arizati/chess.lua

Não há LICENSE nem cabeçalhos. Dizer que é port de chess.js não licencia automaticamente contribuições do port nem restaura o aviso BSD-2-Clause upstream.

**Não copiar na Fase 1** até: (1) autor publicar licença compatível e aviso BSD; (2) substituir por implementação Lua licenciada; ou (3) implementação própria limpa, sem cópia e com diferencial de testes.

## Exact Chess

Declara GNOME Chess/GNOME Games e inclui textos GPLv2/GPLv3/GFDL, mas sem licença raiz/mapeamento inequívoco por arquivo. Além de GTK/engine/PWA incompatíveis, nenhum código/asset será importado; apenas observação visual.

## KOReader e bridge

KOReader é AGPLv3. Plugin GPLv3+ distribuído separadamente é compatível; pacote combinado deve cumprir AGPL aplicável. O repositório adota `GPL-3.0-or-later`, com o texto integral materializado em `LICENSE` na Fase 1.

O snapshot auditado do Kochess fica fixado em `upstream/kochess` como submódulo de proveniência. Ele não entra no pacote instalável. Arquivos efetivamente adaptados precisam manter indicação de origem e autoria no cabeçalho, além do NOTICE.

Antes de release: SBOM/licenças, NOTICE com autores/URLs/commits, source correspondente do Go, verificação asset a asset e prova de ausência de engine.
