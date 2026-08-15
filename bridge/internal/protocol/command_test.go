// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package protocol

import (
	"errors"
	"strings"
	"testing"
)

func validationCode(t *testing.T, err error) string {
	t.Helper()
	if !errors.Is(err, ErrInvalidMessage) {
		t.Fatalf("error %v does not wrap ErrInvalidMessage", err)
	}
	var validation *ValidationError
	if !errors.As(err, &validation) {
		t.Fatalf("error %v is not ValidationError", err)
	}
	return validation.Code
}

func TestDecodeCommandAcceptsKnownFieldsAndIgnoresUnknownFields(t *testing.T) {
	t.Parallel()
	command, err := DecodeCommand([]byte(
		`{"v":1,"type":"move","requestId":"lua-7","gameId":"game_1","move":"e7e8q","future":true}`,
	))
	if err != nil {
		t.Fatal(err)
	}
	if command.Move != "e7e8q" || command.GameID != "game_1" {
		t.Fatalf("unexpected command: %#v", command)
	}
}

func TestDecodeCommandRejectsMalformedEnvelopes(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		line string
		code string
	}{
		{"invalid JSON", `{`, "invalid_json"},
		{"two values", `{"v":1,"type":"connect"} {}`, "invalid_json"},
		{"array", `[]`, "message_not_object"},
		{"version", `{"v":2,"type":"connect"}`, "unsupported_version"},
		{"unknown", `{"v":1,"type":"future"}`, "unknown_type"},
		{"secret", `{"v":1,"type":"connect","nested":{"Authorization":"secret"}}`, "secret_field_forbidden"},
		{"deep object", `{"v":1,"type":"connect","a":{"b":{"c":{"d":{"e":{"f":{"g":{"h":{"i":{}}}}}}}}}}`, "secret_field_forbidden"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := DecodeCommand([]byte(test.line))
			if got := validationCode(t, err); got != test.code {
				t.Fatalf("code = %q, want %q", got, test.code)
			}
		})
	}
}

func TestValidateCommandFields(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		command Command
		code    string
	}{
		{"missing request id", Command{Version: 1, Type: "resign", GameID: "game"}, "invalid_request_id"},
		{"bad game id", Command{Version: 1, Type: "move", RequestID: "r1", GameID: "bad/id", Move: "e2e4"}, "invalid_game_id"},
		{"bad challenge", Command{Version: 1, Type: "accept_challenge", RequestID: "r1"}, "invalid_challenge_id"},
		{"bad move", Command{Version: 1, Type: "move", RequestID: "r1", GameID: "g1", Move: "e2e9"}, "invalid_move"},
		{"bad promotion", Command{Version: 1, Type: "move", RequestID: "r1", GameID: "g1", Move: "e7e8k"}, "invalid_move"},
		{"seek no time", Command{Version: 1, Type: "seek", RequestID: "r1"}, "invalid_time_control"},
		{"seek huge time", Command{Version: 1, Type: "seek", RequestID: "r1", TimeControl: strings.Repeat("x", 33)}, "invalid_time_control"},
		{"challenge no username", Command{Version: 1, Type: "create_challenge", RequestID: "r1"}, "invalid_username"},
		{"challenge short username", Command{Version: 1, Type: "create_challenge", RequestID: "r1", Username: "ab"}, "invalid_username"},
		{"challenge huge username", Command{Version: 1, Type: "create_challenge", RequestID: "r1", Username: strings.Repeat("x", 33)}, "invalid_username"},
		{"challenge bad username", Command{Version: 1, Type: "create_challenge", RequestID: "r1", Username: "bad/user"}, "invalid_username"},
		{"challenge no time", Command{Version: 1, Type: "create_challenge", RequestID: "r1", Username: "opponent"}, "invalid_time_control"},
		{"chat wrong room", Command{Version: 1, Type: "send_chat", RequestID: "r1", GameID: "g1", Room: "spectator", Text: "oi"}, "invalid_chat_room"},
		{"chat empty", Command{Version: 1, Type: "send_chat", RequestID: "r1", GameID: "g1", Room: "player", Text: "  "}, "invalid_chat_text"},
		{"chat control", Command{Version: 1, Type: "send_chat", RequestID: "r1", GameID: "g1", Room: "player", Text: "oi\n"}, "invalid_chat_text"},
		{"missing nonce", Command{Version: 1, Type: "ping"}, "invalid_nonce"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := validationCode(t, ValidateCommand(test.command)); got != test.code {
				t.Fatalf("code = %q, want %q", got, test.code)
			}
		})
	}
}

func TestValidateCommandAcceptsEveryType(t *testing.T) {
	t.Parallel()
	commands := []Command{
		{Version: 1, Type: "connect"},
		{Version: 1, Type: "disconnect"},
		{Version: 1, Type: "accept_challenge", RequestID: "r1", ChallengeID: "c1"},
		{Version: 1, Type: "decline_challenge", RequestID: "r2", ChallengeID: "c1", Reason: "generic"},
		{Version: 1, Type: "open_game", GameID: "g1"},
		{Version: 1, Type: "close_game", GameID: "g1"},
		{Version: 1, Type: "move", RequestID: "r3", GameID: "g1", Move: "e2e4"},
		{Version: 1, Type: "offer_draw", RequestID: "r4", GameID: "g1"},
		{Version: 1, Type: "accept_draw", RequestID: "r5", GameID: "g1"},
		{Version: 1, Type: "decline_draw", RequestID: "r6", GameID: "g1"},
		{Version: 1, Type: "resign", RequestID: "r7", GameID: "g1"},
		{Version: 1, Type: "abort", RequestID: "r8", GameID: "g1"},
		{Version: 1, Type: "seek", RequestID: "r9", TimeControl: "600+5"},
		{Version: 1, Type: "cancel_seek", RequestID: "r10"},
		{Version: 1, Type: "create_challenge", RequestID: "r11", Username: "player-two", TimeControl: "600+5"},
		{Version: 1, Type: "cancel_challenge", RequestID: "r12", ChallengeID: "c9"},
		{Version: 1, Type: "send_chat", RequestID: "r13", GameID: "g1", Room: "player", Text: "Boa partida!"},
		{Version: 1, Type: "ping", Nonce: "n1"},
	}
	for _, command := range commands {
		if err := ValidateCommand(command); err != nil {
			t.Fatalf("%s rejected: %v", command.Type, err)
		}
	}
}
