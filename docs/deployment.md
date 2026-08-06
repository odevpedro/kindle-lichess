# Implantação futura

Não há implantação na Fase 0.

## Permitido

- plugin/bridge: `/mnt/us/koreader/plugins/kindlelichess.koplugin`;
- dados: subdiretório próprio `kindlelichess` resolvido por `DataStorage:getDataDir()`;
- temporários/socket: `/tmp`.

O caminho de dados real do KT4 será consultado somente com autorização, nunca presumido/hardcoded. Token futuro fica em dados próprios, não no plugin versionado.

## Proibido

Sem escrita em `/etc`, `/usr`, `/var/local`, `/opt`, `/root`, `/mnt/us/kmc` ou `chess.koplugin`; sem alterar rootfs, boot, firmware, hotfix, KPM, KOReader original, appreg.db, iptables, SSH ou serviços Amazon.

## Reversão

Fechar UI e confirmar ausência de processo/socket; remover/mover somente plugin e dados próprios; reiniciar KOReader apenas se necessário. Nenhum rollback de sistema, pois não há autostart/instalação de sistema.

Antes da transferência: árvore, scripts integrais, modos, hashes, tamanho, destinos e comandos de reversão; autorização explícita separada.
