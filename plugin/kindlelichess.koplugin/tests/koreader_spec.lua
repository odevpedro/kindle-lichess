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
        assert.is_function(menu_items.kindlelichess.callback)
    end)

    it("builds and updates a 600-pixel e-ink board using real widgets", function()
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
        board.squares.e2:onTapSquare()
        assert.equals("e2", tapped)

        local moved = assert(position:apply_uci("e2e4"))
        board:update(position, moved.dirty, nil, { from = "e2", to = "e4" })
        assert.is_nil(board.squares.e2.piece)
        assert.equals("p", board.squares.e4.piece.type)
        assert.is_true(board.squares.e4.last_move)
        board:free()
    end)

    it("constructs the complete mock session and closes it cleanly", function()
        local Controller = require("controller")
        local MockBridge = require("bridge/mock_bridge")
        local Session = require("ui/session")
        local controller = Controller.new{ monotonic_now = function() return 10 end }
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

        session.board.squares.e2:onTapSquare()
        assert.equals("e2", controller.selection.selected)
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
    end)
end)
