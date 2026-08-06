# ADR-0005 — Bridge limitado à sessão

Status: aceito.

O plugin inicia o bridge ao abrir e encerra ao fechar. Bridge trata SIGTERM, cancela operações, fecha streams/socket e remove seu socket. Sem serviço de boot, hotfix/KPM alterado ou sobrevivência deliberada ao KOReader.
