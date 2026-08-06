# Implantação futura

Não há implantação na Fase 0.

## Permitido

- plugin/bridge: `/mnt/us/koreader/plugins/kindlelichess.koplugin`;
- dados persistentes não secretos: subdiretório próprio resolvido por `DataStorage:getDataDir()`;
- temporários/socket/token privado da sessão: `/tmp`.

O filesystem FSP de `/mnt/us` não preserva modo 0600. O token do protótipo privado não
será persistido nele: ficará em `/tmp/kindle-lichess-token` somente durante a sessão e
será removido ao encerrar. O caminho contém apenas o token, nunca entra no Git ou pacote.

O plugin somente lê o CA bundle já fornecido pelo KOReader em `data/ca-bundle.crt`; não o
copia, substitui ou modifica.

## Proibido

Sem escrita em `/etc`, `/usr`, `/var/local`, `/opt`, `/root`, `/mnt/us/kmc` ou `chess.koplugin`; sem alterar rootfs, boot, firmware, hotfix, KPM, KOReader original, appreg.db, iptables, SSH ou serviços Amazon.

## Reversão

Fechar UI e confirmar ausência de processo/socket; remover/mover somente plugin e dados próprios; reiniciar KOReader apenas se necessário. Nenhum rollback de sistema, pois não há autostart/instalação de sistema.

Antes da transferência: árvore, scripts integrais, modos, hashes, tamanho, destinos e comandos de reversão; autorização explícita separada.
