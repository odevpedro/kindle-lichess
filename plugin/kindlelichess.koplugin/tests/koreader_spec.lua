-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Pedro Schmidt

describe("Kindle Lichess KOReader integration", function()
    local plugin_path = "plugins/kindlelichess.koplugin"
    local original_path

    setup(function()
        require("commonrequire")
        original_path = package.path
        package.path = plugin_path .. "/?.lua;" .. package.path
    end)

    teardown(function()
        package.path = original_path
    end)

    it("loads metadata and registers a Tools menu entry", function()
        local metadata = dofile(plugin_path .. "/_meta.lua")
        assert.equals("Kindle Lichess", metadata.fullname)

        local registered
        local KindleLichess = dofile(plugin_path .. "/main.lua")
        local plugin = KindleLichess:new{
            ui = {
                menu = {
                    registerToMainMenu = function(_, instance)
                        registered = instance
                    end,
                },
            },
        }

        assert.equals(plugin, registered)
        local menu_items = {}
        plugin:addToMainMenu(menu_items)
        assert.equals("Kindle Lichess", menu_items.kindlelichess.text)
        assert.equals("more_tools", menu_items.kindlelichess.sorting_hint)
        assert.equals(3, #menu_items.kindlelichess.sub_item_table)
        assert.equals("Open Kindle Lichess", menu_items.kindlelichess.sub_item_table[1].text)
        assert.is_function(menu_items.kindlelichess.sub_item_table[1].callback)
        assert.is_true(menu_items.kindlelichess.sub_item_table[2].checked_func())
    end)

    it("builds live mode from paths without reading authentication material in Lua", function()
        local Controller = require("controller")
        local KindleLichess = dofile(plugin_path .. "/main.lua")
        local captured
        local expected_bridge = {}
        local plugin = KindleLichess:new{
            path = "/opt/kindlelichess.koplugin",
            data_root = "/koreader",
            bridge_mode = "live",
            token_file = "/data/kindle-lichess/token",
            live_bridge_factory = function(options)
                captured = options
                return expected_bridge
            end,
            ui = { menu = { registerToMainMenu = function() end } },
        }
        local controller = Controller.new{ monotonic_now = function() return 1 end }
        local bridge = plugin:_new_bridge(controller)

        assert.equals(expected_bridge, bridge)
        assert.equals("/opt/kindlelichess.koplugin/bin/kindle-lichess-bridge", captured.binary)
        assert.equals("/data/kindle-lichess/token", captured.token_file)
        assert.equals("/koreader/data/ca-bundle.crt", captured.ca_file)
        assert.equals("/tmp/kindle-lichess.sock", captured.socket_path)
        assert.is_function(captured.emit)
        assert.is_nil(captured.token)
        assert.is_nil(captured.authorization)
    end)

    it("resolves a relative plugin path and defaults to a protected temporary token", function()
        local Controller = require("controller")
        local KindleLichess = dofile(plugin_path .. "/main.lua")
        local captured
        local plugin = KindleLichess:new{
            path = "plugins/kindlelichess.koplugin",
            data_root = "/mnt/us/koreader",
            bridge_mode = "live",
            live_bridge_factory = function(options)
                captured = options
                return {}
            end,
            ui = { menu = { registerToMainMenu = function() end } },
        }
        local controller = Controller.new{ monotonic_now = function() return 1 end }
        plugin:_new_bridge(controller)

        assert.equals("/mnt/us/koreader/plugins/kindlelichess.koplugin/bin/kindle-lichess-bridge",
            captured.binary)
        assert.equals("/tmp/kindle-lichess-token", captured.token_file)
        assert.equals("/mnt/us/koreader/data/ca-bundle.crt", captured.ca_file)
    end)

    it("does not rebuild the challenge widget tree from inside the Accept callback", function()
        local Controller = require("controller")
        local Session = require("ui/session")
        local sent
        local controller = Controller.new{ monotonic_now = function() return 10 end }
        controller:attach_bridge({
            send = function(_, message)
                sent = message
                return true
            end,
        })
        controller.closed = false
        controller.view = "challenge"
        controller.connection = "connected"
        controller.status_text = "Desafio recebido"
        controller.challenge = { id = "challenge01", challenger = { username = "Opponent" } }
        local session = Session:new{ controller = controller }
        local original_root = session[1]
        local accept = session.challenge_actions.button_by_id.accept

        accept.callback()

        assert.equals(original_root, session[1])
        assert.equals("Aceitando desafio…", session.status_widget.text)
        assert.equals("accept_challenge", sent.type)
        assert.equals("challenge01", sent.challengeId)
        session:free()
    end)

    it("builds and updates a 600-pixel e-ink board using real widgets", function()
        local Blitbuffer = require("ffi/blitbuffer")
        local Board = require("ui/board")
        local Position = require("chess/position")
        local position = assert(Position.from_fen("startpos"))
        local tapped
        local board = Board:new{
            position = position,
            orientation = "w",
            board_size = 600,
            on_tap = function(square) tapped = square end,
        }

        assert.equals(600, board:getSize().w)
        assert.equals("r", board.squares.a8.piece.type)
        assert.equals("w", board.squares.e1.piece.color)
        local framebuffer = Blitbuffer.new(600, 600)
        board:paintTo(framebuffer, 0, 0)
        board.squares.e2:onTapSquare()
        assert.equals("e2", tapped)

        board:update(position, {}, "e2", nil, { "e3", "e4" })
        assert.is_true(board.squares.e3.destination)
        assert.is_true(board.squares.e4.destination)
        assert.is_false(board.squares.e5.destination)
        board:paintTo(framebuffer, 0, 0)

        local moved = assert(position:apply_uci("e2e4"))
        board:update(position, moved.dirty, nil, { from = "e2", to = "e4" }, {})
        assert.is_nil(board.squares.e2.piece)
        assert.equals("p", board.squares.e4.piece.type)
        assert.is_true(board.squares.e4.last_move)
        board:free()
        framebuffer:free()
    end)

    it("constructs the complete mock session and closes it cleanly", function()
        local Controller = require("controller")
        local MockBridge = require("bridge/mock_bridge")
        local Session = require("ui/session")
        local now = 10
        local controller = Controller.new{ monotonic_now = function() return now end }
        local bridge = MockBridge.new{
            emit = function(message) controller:handle(message) end,
        }
        controller:attach_bridge(bridge)
        local session = Session:new{ controller = controller }

        controller:start()
        assert.equals("challenge", controller.view)
        controller:accept_challenge()
        assert.equals("game", controller.view)
        assert.is_not_nil(session.board)
        assert.equals("w", session.board.orientation)
        assert.equals(15, Session.clock_refresh_interval(600000))
        assert.equals(5, Session.clock_refresh_interval(300000))
        assert.equals(2, Session.clock_refresh_interval(60000))
        local screen = require("device").screen
        local framebuffer = require("ffi/blitbuffer").new(screen:getWidth(), screen:getHeight())
        session:paintTo(framebuffer, 0, 0)
        assert.equals("KindleTester  10:00", session.bottom_clock:getText())
        now = 25
        session.clock_callback()
        assert.equals("KindleTester  09:45", session.bottom_clock:getText())

        session.board.squares.e2:onTapSquare()
        assert.equals("e2", controller.selection.selected)
        assert.is_true(session.board.squares.e3.destination)
        assert.is_true(session.board.squares.e4.destination)
        session.board.squares.e4:onTapSquare()
        assert.equals(2, #controller.game_state.moves)
        assert.equals("p", controller.game_state.position:piece_at("e4").type)
        assert.equals("p", controller.game_state.position:piece_at("e5").type)

        controller:simulate_disconnect()
        assert.equals("connected", controller.connection)
        assert.equals("game", controller.view)
        assert.equals(2, #controller.game_state.moves)

        controller:offer_draw()
        assert.equals("result", controller.view)
        assert.equals("Empate", controller.status_text)

        session:onCloseWidget()
        assert.is_true(controller.closed)
        assert.is_false(bridge.alive)
        assert.is_nil(next(bridge.scheduled))
        session:free()
        framebuffer:free()
    end)

    it("frames nonblocking Unix JSONL traffic without crashing on invalid input", function()
        local rapidjson = require("rapidjson")
        local SocketBridge = require("bridge/socket_bridge")
        local attempts, scheduled, events, writes = 0, {}, {}, ""
        local active_transport
        local function transport_factory()
            attempts = attempts + 1
            local transport = {
                chunks = {},
                closed = false,
                connect = function() return attempts >= 3 end,
                close = function(self) self.closed = true end,
                write = function(_, data)
                    local count = math.min(7, #data)
                    writes = writes .. data:sub(1, count)
                    return count
                end,
                read = function(self)
                    if #self.chunks == 0 then return "", "again" end
                    return table.remove(self.chunks, 1)
                end,
            }
            if attempts >= 3 then active_transport = transport end
            return transport
        end
        local registered, unregistered = false, false
        local bridge
        bridge = SocketBridge.new{
            emit = function(message) events[#events + 1] = message end,
            transport_factory = transport_factory,
            schedule = function(_, callback) scheduled[#scheduled + 1] = callback end,
            cancel = function() end,
            register = function(instance)
                assert.equals(bridge, instance)
                registered = true
            end,
            unregister = function(instance)
                assert.equals(bridge, instance)
                unregistered = true
            end,
            encode = rapidjson.encode,
            decode = rapidjson.decode,
        }

        assert.is_true(bridge:start())
        assert.is_true(bridge:send({ v = 1, type = "connect" }))
        assert.equals(1, #scheduled)
        table.remove(scheduled, 1)()
        assert.equals(1, #scheduled)
        table.remove(scheduled, 1)()
        assert.is_true(bridge.connected)
        assert.is_true(registered)
        local sent = assert(rapidjson.decode(writes))
        assert.equals("connect", sent.type)
        assert.equals(1, sent.v)

        local connected = rapidjson.encode({
            v = 1, type = "connected",
            account = { id = "tester01", username = "Tester", future = true },
        })
        local pong = rapidjson.encode({ v = 1, type = "pong", nonce = "n1" })
        active_transport.chunks = {
            "\n" .. connected:sub(1, 13),
            connected:sub(14) .. "\r\n" .. pong .. "\n{bad json}\n",
        }
        bridge:waitEvent()
        assert.equals("connected", events[1].type)
        assert.equals("pong", events[2].type)
        assert.equals("error", events[3].type)
        assert.equals("invalid_json", events[3].code)

        bridge.max_message_bytes = 16
        bridge:_consume(string.rep("x", 16))
        assert.is_false(bridge.connected)
        assert.equals("message_too_large", events[#events].code)
        assert.is_true(events[#events].fatal)
        local sent_after_failure, send_error = bridge:send({ v = 1, type = "connect" })
        assert.is_nil(sent_after_failure)
        assert.equals("socket_unavailable", send_error)
        bridge:close()
        assert.is_true(unregistered)
        assert.is_true(active_transport.closed)
    end)

    it("starts and terminates the bridge as one supervised process group", function()
        local Process = require("bridge/process")
        local callbacks, killed, done_checks = {}, {}, 0
        local fake_util = {
            runInSubProcess = function(callback)
                assert.is_function(callback)
                return 42
            end,
            isSubProcessDone = function(pid)
                assert.equals(42, pid)
                done_checks = done_checks + 1
                return done_checks >= 2
            end,
            terminateSubProcess = function() error("unexpected forced termination") end,
        }
        local process = Process.new{
            binary = "/plugin/kindle-lichess-bridge",
            token_file = "/data/token",
            ca_file = "/koreader/data/ca-bundle.crt",
            socket_path = "/tmp/kindle-lichess.sock",
            util = fake_util,
            kill = function(pid, signal)
                killed = { pid = pid, signal = signal }
                return 0
            end,
            schedule = function(_, callback) callbacks[#callbacks + 1] = callback end,
        }
        assert.is_true(process:start())
        process:stop()
        assert.equals(-42, killed.pid)
        assert.equals(15, killed.signal)
        table.remove(callbacks, 1)()
        table.remove(callbacks, 1)()
        assert.equals(2, done_checks)
    end)

    it("exchanges bytes through a real nonblocking Unix socket", function()
        local ffi = require("ffi")
        local UnixTransport = require("bridge/unix_transport")
        require("ffi/posix_h")
        ffi.cdef[[
            int bind(int, const struct sockaddr *, socklen_t);
            int listen(int, int);
            int accept(int, struct sockaddr *, socklen_t *);
        ]]
        local C = ffi.C
        local path = "/tmp/kindle-lichess-spec-" .. tostring(C.getpid()) .. ".sock"
        os.remove(path)
        local server_fd, client_fd = -1, -1
        local transport
        local ok, err = xpcall(function()
            server_fd = C.socket(C.KINDLE_LICHESS_AF_UNIX, C.KINDLE_LICHESS_SOCK_STREAM, 0)
            assert.is_true(server_fd >= 0)
            local address = ffi.new("struct sockaddr_un")
            address.sun_family = C.KINDLE_LICHESS_AF_UNIX
            ffi.copy(address.sun_path, path, #path)
            assert.equals(0, C.bind(server_fd,
                ffi.cast("const struct sockaddr *", address), ffi.sizeof(address)))
            assert.equals(0, C.listen(server_fd, 1))

            transport = UnixTransport.new(path)
            assert.is_true(transport:connect())
            client_fd = C.accept(server_fd, nil, nil)
            assert.is_true(client_fd >= 0)
            assert.equals(5, transport:write("ping\n"))
            local buffer = ffi.new("uint8_t[16]")
            local count = C.read(client_fd, buffer, 16)
            assert.equals("ping\n", ffi.string(buffer, count))
            assert.equals(5, C.write(client_fd, "pong\n", 5))
            local reply = assert(transport:read(16))
            assert.equals("pong\n", reply)
        end, debug.traceback)
        if transport then transport:close() end
        if client_fd >= 0 then C.close(client_fd) end
        if server_fd >= 0 then C.close(server_fd) end
        os.remove(path)
        assert.is_true(ok, err)
    end)
end)
