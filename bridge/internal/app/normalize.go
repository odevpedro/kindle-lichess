// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package app

import (
	"encoding/json"

	"github.com/odevpedro/kindle-lichess/bridge/internal/lichess"
)

type apiUser struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Name     string `json:"name"`
	Title    string `json:"title,omitempty"`
	Rating   int    `json:"rating,omitempty"`
}

func (user apiUser) normalized() map[string]any {
	username := user.Username
	if username == "" {
		username = user.Name
	}
	result := map[string]any{"id": user.ID, "username": username}
	if user.Title != "" {
		result["title"] = user.Title
	}
	if user.Rating != 0 {
		result["rating"] = user.Rating
	}
	return result
}

func normalizeChallenge(raw json.RawMessage) (map[string]any, error) {
	var challenge struct {
		ID          string          `json:"id"`
		Direction   string          `json:"direction"`
		Status      string          `json:"status"`
		Rated       bool            `json:"rated"`
		Speed       string          `json:"speed"`
		Color       string          `json:"color"`
		Variant     json.RawMessage `json:"variant"`
		TimeControl json.RawMessage `json:"timeControl"`
		Challenger  apiUser         `json:"challenger"`
	}
	if err := json.Unmarshal(raw, &challenge); err != nil || challenge.ID == "" {
		return nil, &lichess.APIError{Code: "invalid_response"}
	}
	return map[string]any{
		"id": challenge.ID, "direction": challenge.Direction, "status": challenge.Status,
		"rated": challenge.Rated, "speed": challenge.Speed, "color": challenge.Color,
		"variant": variantKey(challenge.Variant), "timeControl": rawObject(challenge.TimeControl),
		"challenger": challenge.Challenger.normalized(),
	}, nil
}

func normalizeGameReference(raw json.RawMessage) (map[string]any, error) {
	var game struct {
		ID     string `json:"id"`
		Status string `json:"status,omitempty"`
		Winner string `json:"winner,omitempty"`
		Color  string `json:"color,omitempty"`
	}
	if err := json.Unmarshal(raw, &game); err != nil || game.ID == "" {
		return nil, &lichess.APIError{Code: "invalid_response"}
	}
	result := map[string]any{"id": game.ID}
	if game.Status != "" {
		result["status"] = game.Status
	}
	if game.Winner != "" {
		result["winner"] = game.Winner
	}
	if game.Color != "" {
		result["color"] = game.Color
	}
	return result, nil
}

func objectID(raw json.RawMessage) (string, error) {
	var object struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(raw, &object); err != nil || object.ID == "" {
		return "", &lichess.APIError{Code: "invalid_response"}
	}
	return object.ID, nil
}

func (s *Session) normalizeGameFull(raw json.RawMessage) (map[string]any, bool, error) {
	var full struct {
		ID         string          `json:"id"`
		Variant    json.RawMessage `json:"variant"`
		Speed      string          `json:"speed"`
		Rated      bool            `json:"rated"`
		CreatedAt  int64           `json:"createdAt,omitempty"`
		InitialFen string          `json:"initialFen"`
		White      apiUser         `json:"white"`
		Black      apiUser         `json:"black"`
		State      json.RawMessage `json:"state"`
	}
	if err := json.Unmarshal(raw, &full); err != nil || full.ID == "" {
		return nil, false, &lichess.APIError{Code: "invalid_response"}
	}
	state, terminal, err := normalizeGameState(full.State)
	if err != nil {
		return nil, false, err
	}
	initialFen := full.InitialFen
	if initialFen == "" {
		initialFen = "startpos"
	}
	color := ""
	s.mutex.Lock()
	if s.account != nil {
		if full.White.ID == s.account.ID {
			color = "w"
		} else if full.Black.ID == s.account.ID {
			color = "b"
		}
	}
	s.mutex.Unlock()
	return map[string]any{
		"id": full.ID, "variant": variantKey(full.Variant), "speed": full.Speed,
		"rated": full.Rated, "createdAt": full.CreatedAt, "initialFen": initialFen,
		"color": color, "white": full.White.normalized(), "black": full.Black.normalized(),
		"state": state,
	}, terminal, nil
}

func normalizeGameState(raw json.RawMessage) (map[string]any, bool, error) {
	var state struct {
		Moves      string `json:"moves"`
		WhiteTime  int64  `json:"wtime"`
		BlackTime  int64  `json:"btime"`
		WhiteInc   int64  `json:"winc"`
		BlackInc   int64  `json:"binc"`
		Status     string `json:"status"`
		Winner     string `json:"winner,omitempty"`
		WhiteDraw  bool   `json:"wdraw,omitempty"`
		BlackDraw  bool   `json:"bdraw,omitempty"`
		Expiration int64  `json:"expiration,omitempty"`
	}
	if err := json.Unmarshal(raw, &state); err != nil || state.Status == "" {
		return nil, false, &lichess.APIError{Code: "invalid_response"}
	}
	result := map[string]any{
		"moves": state.Moves, "wtime": state.WhiteTime, "btime": state.BlackTime,
		"winc": state.WhiteInc, "binc": state.BlackInc, "status": state.Status,
	}
	if state.Winner != "" {
		result["winner"] = state.Winner
	}
	if state.WhiteDraw {
		result["wdraw"] = true
	}
	if state.BlackDraw {
		result["bdraw"] = true
	}
	if state.Expiration != 0 {
		result["expiration"] = state.Expiration
	}
	return result, state.Status != "started" && state.Status != "created", nil
}

func variantKey(raw json.RawMessage) string {
	var direct string
	if json.Unmarshal(raw, &direct) == nil && direct != "" {
		return direct
	}
	var object struct {
		Key string `json:"key"`
	}
	_ = json.Unmarshal(raw, &object)
	return object.Key
}

func rawObject(raw json.RawMessage) any {
	var value any
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &value)
	}
	return value
}
