-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

-- The English source string is the stable translation key and universal
-- fallback. The plugin ships its own catalog because external KOReader plugins
-- are not part of KOReader's compiled gettext domain.
local I18n = {}

local language_override

local pt_BR = {
    ["Open Kindle Lichess"] = "Abrir Kindle Lichess",
    ["Free board"] = "Tabuleiro livre",
    ["Mock mode"] = "Modo simulado",
    ["Lichess test account"] = "Conta de teste do Lichess",
    ["Uses a temporary 0600 token file and the official Board API."] =
        "Usa um arquivo temporário de token 0600 e a Board API oficial.",
    ["Language"] = "Idioma",
    ["Automatic (KOReader)"] = "Automático (KOReader)",
    ["English"] = "Inglês",
    ["Portuguese (Brazil)"] = "Português (Brasil)",
    ["Export sanitized diagnostics"] = "Exportar diagnóstico sanitizado",
    ["Sanitized diagnostics saved to %{path}"] =
        "Diagnóstico sanitizado salvo em %{path}",
    ["Could not save diagnostics: %{error}"] =
        "Não foi possível salvar o diagnóstico: %{error}",

    ["connected"] = "conectado",
    ["connecting"] = "conectando",
    ["reconnecting"] = "reconectando",
    ["offline"] = "offline",
    ["Cancel search"] = "Cancelar busca",
    ["Play someone (%{time})"] = "Jogar com alguém (%{time})",
    ["Challenge player…"] = "Desafiar jogador…",
    ["Time: %{time}"] = "Tempo: %{time}",
    ["Cancel challenge"] = "Cancelar desafio",
    ["%{username} challenges you\nRapid • 10+5 • Casual"] =
        "%{username} desafia você\nRápida • 10+5 • Casual",
    ["Opponent"] = "Adversário",
    ["Decline"] = "Recusar",
    ["Accept"] = "Aceitar",
    ["Close"] = "Fechar",
    ["Player"] = "Jogador",
    ["Reviewing move %{current}/%{total}"] = "Revendo lance %{current}/%{total}",
    ["Save PGN"] = "Salvar PGN",
    ["Queen"] = "Dama",
    ["Rook"] = "Torre",
    ["Bishop"] = "Bispo",
    ["Knight"] = "Cavalo",
    ["Abort"] = "Abortar",
    ["Resign"] = "Desistir",
    ["Chat"] = "Chat",
    ["Chat (%{count})"] = "Chat (%{count})",
    ["Draw"] = "Empate",
    ["Reconnect"] = "Reconectar",
    ["Back to board"] = "Voltar ao tabuleiro",
    ["Write…"] = "Escrever…",
    ["Game chat — players only"] = "Chat da partida — somente jogadores",
    ["Move"] = "Mover",
    ["Erase"] = "Apagar",
    ["Clear"] = "Limpar",
    ["Initial"] = "Inicial",
    ["Toggle turn"] = "Alternar turno",
    ["Edit FEN…"] = "Editar FEN…",

    ["Use minutes+increment, for example 10+5"] =
        "Use o formato minutos+incremento, por exemplo 10+5",
    ["Initial time exceeds the Lichess limit"] =
        "Tempo inicial acima do permitido pelo Lichess",
    ["Initial time is not accepted by Lichess"] =
        "Tempo inicial não aceito pelo Lichess",
    ["Increment exceeds the Lichess limit"] =
        "Incremento acima do permitido pelo Lichess",
    ["This time control is too fast for this Board API mode"] =
        "Este tempo é rápido demais para este modo da Board API",
    ["The time must result in whole seconds"] =
        "O tempo precisa resultar em segundos inteiros",
    ["The message must contain 1 to 280 bytes and no line breaks"] =
        "A mensagem deve ter de 1 a 280 bytes, sem quebras de linha",
    ["Invalid chat room"] = "Sala de chat inválida",
    ["Chat is unavailable on this screen"] = "Chat indisponível nesta tela",
    ["Wait for the previous message to be sent"] =
        "Aguarde o envio da mensagem anterior",
    ["Failed: %{error}"] = "Falha: %{error}",
    ["Opponent username"] = "Nome do adversário",
    ["Lichess username, e.g. MagnusCarlsen"] =
        "Usuário do Lichess, por exemplo MagnusCarlsen",
    ["Cancel"] = "Cancelar",
    ["Challenge"] = "Desafiar",
    ["Custom time"] = "Tempo personalizado",
    ["Format: minutes+increment, for example 10+5. Public search accepts Rapid or slower."] =
        "Formato minutos+incremento, por exemplo 10+5. Busca pública aceita Rápida ou mais lenta.",
    ["Apply"] = "Aplicar",
    ["FEN position"] = "Posição FEN",
    ["Edit all six FEN fields and tap Apply."] =
        "Edite os seis campos FEN e toque em Aplicar.",
    ["Message to opponent"] = "Mensagem ao adversário",
    ["Private game chat. Be kind and follow the Lichess rules."] =
        "Chat privado da partida. Seja gentil e siga as regras do Lichess.",
    ["Send"] = "Enviar",
    ["Abort this game?"] = "Abortar esta partida?",
    ["Resign this game?"] = "Desistir desta partida?",

    ["Lichess rejected the action; the challenge may have expired"] =
        "Lichess recusou a ação; o desafio pode ter expirado",
    ["No Lichess token was found. Add the token and reopen the plugin"] =
        "Nenhum token do Lichess foi encontrado. Adicione o token e reabra o plugin",
    ["The token file permissions are unsafe. Set mode 0600 and try again"] =
        "As permissões do token são inseguras. Defina o modo 0600 e tente novamente",
    ["The token file is invalid. Create a new token with board:play access"] =
        "O arquivo de token é inválido. Crie um novo token com acesso board:play",
    ["Token rejected by Lichess"] = "Token recusado pelo Lichess",
    ["Token lacks the board:play permission"] = "Token sem permissão board:play",
    ["Challenge or game not found"] = "Desafio ou partida não encontrado",
    ["Too many requests; wait and try again"] =
        "Muitas solicitações; aguarde e tente novamente",
    ["Lichess response timed out"] = "Tempo de resposta do Lichess esgotado",
    ["Network failure while accessing Lichess"] = "Falha de rede ao acessar o Lichess",
    ["Lichess is temporarily unavailable. Wait and try again"] =
        "O Lichess está temporariamente indisponível. Aguarde e tente novamente",
    ["Bridge is not connected yet"] = "Bridge ainda não conectado",
    ["The local bridge could not be started. Restart KOReader"] =
        "Não foi possível iniciar o bridge local. Reinicie o KOReader",
    ["The local bridge is unavailable. Restart KOReader and check the token"] =
        "O bridge local está indisponível. Reinicie o KOReader e verifique o token",
    ["Another bridge is already using the local socket. Restart KOReader"] =
        "Outro bridge já está usando o socket local. Reinicie o KOReader",
    ["The local bridge socket is unsafe. Restart KOReader"] =
        "O socket do bridge local é inseguro. Reinicie o KOReader",
    ["The local bridge stopped. Reopen the plugin"] =
        "O bridge local parou. Reabra o plugin",
    ["The local bridge connection failed while reading. Reopen the plugin"] =
        "A conexão com o bridge falhou durante a leitura. Reabra o plugin",
    ["The local bridge connection failed while writing. Reopen the plugin"] =
        "A conexão com o bridge falhou durante a escrita. Reabra o plugin",
    ["KOReader's certificate file is invalid or unavailable"] =
        "O arquivo de certificados do KOReader é inválido ou está indisponível",
    ["The bridge returned an invalid message. Reopen the plugin"] =
        "O bridge retornou uma mensagem inválida. Reabra o plugin",
    ["Lichess returned an unsupported response"] =
        "O Lichess retornou uma resposta incompatível",
    ["A bridge message exceeded the safe size limit"] =
        "Uma mensagem do bridge excedeu o limite seguro",
    ["The bridge encountered an internal error. Reopen the plugin"] =
        "O bridge encontrou um erro interno. Reabra o plugin",
    ["Unexpected bridge error"] = "Erro inesperado do bridge",
    ["%{message} (%{code})"] = "%{message} (%{code})",

    ["by checkmate"] = "por cheque-mate",
    ["by resignation"] = "por desistência",
    ["on time"] = "por tempo esgotado",
    ["by illegal move"] = "por lance ilegal",
    ["by stalemate"] = "por afogamento",
    ["White"] = "Brancas",
    ["Black"] = "Pretas",
    ["Victory for %{color}"] = "Vitória das %{color}",
    ["Game aborted"] = "Partida abortada",
    ["Drawn game"] = "Empate",
    ["Closed"] = "Fechado",
    ["Connecting…"] = "Conectando…",
    ["Failed to start: %{error}"] = "Falha ao iniciar: %{error}",
    ["Accepting challenge…"] = "Aceitando desafio…",
    ["Sending %{move}…"] = "Enviando %{move}…",
    ["Move not sent"] = "Jogada não enviada",
    ["Sending promotion…"] = "Enviando promoção…",
    ["Time set: %{time}"] = "Tempo definido: %{time}",
    ["Searching for an opponent (%{time} casual)…"] =
        "Procurando adversário (%{time} casual)…",
    ["Search canceled"] = "Busca cancelada",
    ["Challenging %{username}…"] = "Desafiando %{username}…",
    ["Canceling challenge…"] = "Cancelando desafio…",
    ["PGN saved to %{path}"] = "PGN salvo em %{path}",
    ["No messages in this game."] = "Nenhuma mensagem nesta partida.",
    ["Free board — move pieces"] = "Tabuleiro livre — mover peças",
    ["Move pieces"] = "Mover peças",
    ["Erase pieces"] = "Apagar peças",
    ["Add %{piece}"] = "Adicionar %{piece}",
    ["White to move"] = "Brancas jogam",
    ["Black to move"] = "Pretas jogam",
    ["FEN loaded"] = "FEN carregada",
    ["Your turn"] = "Sua vez",
    ["Opponent's turn"] = "Vez do adversário",
    ["Game finished"] = "Partida encerrada",
    ["Invalid bridge message"] = "Mensagem inválida do bridge",
    ["Connected as %{username}"] = "Conectado como %{username}",
    ["Challenge sent, waiting for acceptance…"] =
        "Desafio enviado, aguardando aceite…",
    ["Challenge received"] = "Desafio recebido",
    ["Challenge declined"] = "Desafio recusado",
    ["Challenge canceled"] = "Desafio cancelado",
    ["Opening game…"] = "Abrindo partida…",
    ["Incompatible game: %{error}"] = "Partida incompatível: %{error}",
    ["Invalid state: %{error}"] = "Estado inválido: %{error}",
    ["Move rejected"] = "Jogada recusada",
    ["Reconnecting in %{seconds} s…"] = "Reconectando em %{seconds} s…",
    ["Reconnecting…"] = "Reconectando…",
    ["Victory"] = "Vitória",
    ["Defeat"] = "Derrota",
    ["Opponent disconnected"] = "Adversário desconectado",
    ["Opponent reconnected"] = "Adversário reconectou",

    ["Play human chess games on Lichess with an e-ink interface."] =
        "Jogue partidas de xadrez contra pessoas no Lichess em uma interface e-ink.",
}

local function normalize(language)
    if type(language) ~= "string" then return "en" end
    local value = language:gsub("-", "_"):lower()
    if value == "pt" or value:match("^pt_br") then return "pt_BR" end
    return "en"
end

local function read_setting(name)
    local settings = rawget(_G, "G_reader_settings")
    if not settings or type(settings.readSetting) ~= "function" then return nil end
    local ok, value = pcall(settings.readSetting, settings, name)
    return ok and value or nil
end

function I18n.language()
    local configured = language_override
    if configured == nil then configured = read_setting("kindlelichess_language") end
    if configured and configured ~= "auto" then return normalize(configured) end
    return normalize(read_setting("language"))
end

function I18n.set_language(language)
    language_override = language or "auto"
end

function I18n.normalize(language)
    return normalize(language)
end

function I18n.t(source, values)
    local template = source
    if I18n.language() == "pt_BR" then template = pt_BR[source] or source end
    local rendered = template:gsub("%%{([%w_]+)}", function(name)
        local value = values and values[name]
        return value == nil and ("%{" .. name .. "}") or tostring(value)
    end)
    return rendered
end

function I18n.has_translation(source, language)
    return normalize(language) == "en" or pt_BR[source] ~= nil
end

return I18n
