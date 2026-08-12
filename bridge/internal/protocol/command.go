// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

// Package protocol defines the versioned JSON contract between the Lua plugin and bridge.
package protocol

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

const Version = 1

var ErrInvalidMessage = errors.New("invalid_protocol_message")

type Command struct {
	Version     int    `json:"v"`
	Type        string `json:"type"`
	RequestID   string `json:"requestId,omitempty"`
	ChallengeID string `json:"challengeId,omitempty"`
	GameID      string `json:"gameId,omitempty"`
	Move        string `json:"move,omitempty"`
	Reason      string `json:"reason,omitempty"`
	Rated       bool   `json:"rated,omitempty"`
	TimeControl string `json:"timeControl,omitempty"`
	Username    string `json:"username,omitempty"`
	Nonce       string `json:"nonce,omitempty"`
}

var commandTypes = map[string]bool{
	"connect": true, "disconnect": true, "accept_challenge": true,
	"decline_challenge": true, "open_game": true, "close_game": true,
	"move": true, "offer_draw": true, "accept_draw": true,
	"decline_draw": true, "resign": true, "abort": true, "seek": true,
	"cancel_seek": true, "create_challenge": true, "cancel_challenge": true,
	"ping": true,
}

var mutatingCommands = map[string]bool{
	"accept_challenge": true, "decline_challenge": true, "move": true,
	"offer_draw": true, "accept_draw": true, "decline_draw": true,
	"resign": true, "abort": true, "seek": true, "cancel_seek": true,
	"create_challenge": true, "cancel_challenge": true,
}

var gameCommands = map[string]bool{
	"open_game": true, "close_game": true, "move": true, "offer_draw": true,
	"accept_draw": true, "decline_draw": true, "resign": true, "abort": true,
}

type ValidationError struct {
	Code string
}

func (e *ValidationError) Error() string { return e.Code }
func (e *ValidationError) Unwrap() error { return ErrInvalidMessage }

func invalid(code string) error { return &ValidationError{Code: code} }

func DecodeCommand(line []byte) (Command, error) {
	var raw any
	decoder := json.NewDecoder(bytes.NewReader(line))
	decoder.UseNumber()
	if err := decoder.Decode(&raw); err != nil {
		return Command{}, invalid("invalid_json")
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return Command{}, invalid("invalid_json")
	}
	object, ok := raw.(map[string]any)
	if !ok {
		return Command{}, invalid("message_not_object")
	}
	if containsSecret(object, 0) {
		return Command{}, invalid("secret_field_forbidden")
	}

	var command Command
	if err := json.Unmarshal(line, &command); err != nil {
		return Command{}, invalid("invalid_json")
	}
	if err := ValidateCommand(command); err != nil {
		return Command{}, err
	}
	return command, nil
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var extra any
	err := decoder.Decode(&extra)
	if errors.Is(err, io.EOF) {
		return nil
	}
	return fmt.Errorf("extra JSON value")
}

func containsSecret(value any, depth int) bool {
	if depth > 8 {
		return true
	}
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			switch strings.ToLower(key) {
			case "token", "authorization", "access_token":
				return true
			}
			if containsSecret(child, depth+1) {
				return true
			}
		}
	case []any:
		for _, child := range typed {
			if containsSecret(child, depth+1) {
				return true
			}
		}
	}
	return false
}

func ValidateCommand(command Command) error {
	if command.Version != Version {
		return invalid("unsupported_version")
	}
	if len(command.Type) < 1 || len(command.Type) > 64 {
		return invalid("invalid_type")
	}
	if !commandTypes[command.Type] {
		return invalid("unknown_type")
	}
	if mutatingCommands[command.Type] && !validID(command.RequestID, 64) {
		return invalid("invalid_request_id")
	}
	if gameCommands[command.Type] && !validID(command.GameID, 32) {
		return invalid("invalid_game_id")
	}
	if (command.Type == "accept_challenge" || command.Type == "decline_challenge" ||
		command.Type == "cancel_challenge") &&
		!validID(command.ChallengeID, 32) {
		return invalid("invalid_challenge_id")
	}
	if command.Type == "move" && !validUCI(command.Move) {
		return invalid("invalid_move")
	}
	if command.Type == "decline_challenge" && command.Reason != "" && len(command.Reason) > 64 {
		return invalid("invalid_reason")
	}
	if command.Type == "seek" && (len(command.TimeControl) < 1 || len(command.TimeControl) > 32) {
		return invalid("invalid_time_control")
	}
	if command.Type == "create_challenge" && !validUsername(command.Username) {
		return invalid("invalid_username")
	}
	if command.Type == "create_challenge" && (len(command.TimeControl) < 1 || len(command.TimeControl) > 32) {
		return invalid("invalid_time_control")
	}
	if command.Type == "ping" && (len(command.Nonce) < 1 || len(command.Nonce) > 64) {
		return invalid("invalid_nonce")
	}
	return nil
}

func validID(value string, maximum int) bool {
	if len(value) < 1 || len(value) > maximum {
		return false
	}
	for _, character := range []byte(value) {
		if (character < 'a' || character > 'z') && (character < 'A' || character > 'Z') &&
			(character < '0' || character > '9') && character != '_' && character != '-' {
			return false
		}
	}
	return true
}

func validUsername(value string) bool {
	// Lichess usernames: 3+ visible, allow letters/digits/-/_ and some Unicode.
	// Keep transport-level check conservative ASCII to avoid encoding surprises.
	if len(value) < 3 || len(value) > 32 {
		return false
	}
	for _, character := range []byte(value) {
		if (character < 'a' || character > 'z') && (character < 'A' || character > 'Z') &&
			(character < '0' || character > '9') && character != '_' && character != '-' {
			return false
		}
	}
	return true
}

func validUCI(move string) bool {
	if len(move) != 4 && len(move) != 5 {
		return false
	}
	for _, offset := range []int{0, 2} {
		if move[offset] < 'a' || move[offset] > 'h' || move[offset+1] < '1' || move[offset+1] > '8' {
			return false
		}
	}
	return len(move) == 4 || strings.ContainsRune("qrbn", rune(move[4]))
}
