// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

// Package app coordinates one plugin session. It contains no process-global daemon state.
package app

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net"
	"sync"
	"time"

	"github.com/odevpedro/kindle-lichess/bridge/internal/ipc"
	"github.com/odevpedro/kindle-lichess/bridge/internal/lichess"
	"github.com/odevpedro/kindle-lichess/bridge/internal/protocol"
	"github.com/odevpedro/kindle-lichess/bridge/internal/reconnect"
	"github.com/odevpedro/kindle-lichess/bridge/internal/stream"
)

var errDisconnect = errors.New("plugin_disconnect")

const maxRequestAttempts = 3

type API interface {
	Account(context.Context) (lichess.Account, error)
	StreamAccount(context.Context, func(lichess.RawEvent) error) error
	StreamGame(context.Context, string, func(lichess.RawEvent) error) error
	AcceptChallenge(context.Context, string) error
	DeclineChallenge(context.Context, string, string) error
	CreateSeek(context.Context, lichess.SeekOptions) error
	CancelSeek(context.Context) error
	Move(context.Context, string, string) error
	Draw(context.Context, string, bool) error
	Resign(context.Context, string) error
	Abort(context.Context, string) error
}

type Session struct {
	api        API
	policy     reconnect.Policy
	connection *ipc.Connection

	context context.Context
	cancel  context.CancelFunc
	wait    sync.WaitGroup

	mutex         sync.Mutex
	account       *lichess.Account
	accountCancel context.CancelFunc
	gameCancel    context.CancelFunc
	gameID        string
	results       map[string]map[string]any
	resultOrder   []string
	mutationMutex sync.Mutex
}

func NewSession(api API, policy reconnect.Policy) *Session {
	if policy.Sleep == nil {
		policy.Sleep = reconnect.DefaultPolicy().Sleep
	}
	return &Session{api: api, policy: policy, results: make(map[string]map[string]any)}
}

func (s *Session) Run(ctx context.Context, connection net.Conn) error {
	s.context, s.cancel = context.WithCancel(ctx)
	s.connection = ipc.NewConnection(connection)
	err := s.connection.ReadCommands(s.context, s.handleCommand)
	s.cancel()
	s.wait.Wait()
	if errors.Is(err, errDisconnect) || (errors.Is(err, context.Canceled) && ctx.Err() == nil) {
		return nil
	}
	return err
}

func (s *Session) handleCommand(ctx context.Context, command protocol.Command) error {
	switch command.Type {
	case "connect":
		return s.connect(ctx)
	case "disconnect":
		_ = s.send(map[string]any{
			"v": 1, "type": "disconnected", "reason": "closed_by_plugin",
		})
		return errDisconnect
	case "open_game":
		if !s.connected() {
			return s.send(errorCodeMessage("not_connected", "", false))
		}
		s.openGame(command.GameID)
		return nil
	case "close_game":
		s.closeGame(command.GameID)
		return nil
	case "ping":
		return s.send(map[string]any{"v": 1, "type": "pong", "nonce": command.Nonce})
	default:
		return s.mutate(ctx, command)
	}
}

func (s *Session) connect(ctx context.Context) error {
	s.mutex.Lock()
	account := s.account
	s.mutex.Unlock()
	if account != nil {
		return s.send(map[string]any{"v": 1, "type": "connected", "account": account})
	}
	var loaded lichess.Account
	err := reconnect.Run(ctx, s.policy, func(requestContext context.Context) error {
		var requestErr error
		loaded, requestErr = s.api.Account(requestContext)
		return requestErr
	}, retryDecision, func(attempt int, delay time.Duration, _ error) {
		s.notifyReconnect("account", attempt, delay)
	})
	if err != nil {
		return s.sendAPIError(err, "", false)
	}
	s.mutex.Lock()
	s.account = &loaded
	streamContext, cancel := context.WithCancel(s.context)
	s.accountCancel = cancel
	s.mutex.Unlock()
	if err := s.send(map[string]any{"v": 1, "type": "connected", "account": loaded}); err != nil {
		cancel()
		return err
	}
	s.wait.Add(1)
	go func() {
		defer s.wait.Done()
		err := s.runAccountStream(streamContext)
		if err != nil && !errors.Is(err, context.Canceled) {
			_ = s.sendAPIError(err, "", true)
		}
	}()
	return nil
}

func (s *Session) runAccountStream(ctx context.Context) error {
	return reconnect.Run(ctx, s.policy, func(operationContext context.Context) error {
		return s.api.StreamAccount(operationContext, s.handleAccountEvent)
	}, retryDecision, func(attempt int, delay time.Duration, _ error) {
		s.notifyReconnect("account", attempt, delay)
	})
}

func (s *Session) handleAccountEvent(event lichess.RawEvent) error {
	var payload struct {
		Challenge json.RawMessage `json:"challenge"`
		Game      json.RawMessage `json:"game"`
	}
	if err := json.Unmarshal(event.JSON, &payload); err != nil {
		return &lichess.APIError{Code: "invalid_json"}
	}
	switch event.Type {
	case "challenge":
		challenge, err := normalizeChallenge(payload.Challenge)
		if err != nil {
			return err
		}
		return s.send(map[string]any{"v": 1, "type": "challenge", "challenge": challenge})
	case "challengeCanceled":
		challengeID, err := objectID(payload.Challenge)
		if err != nil {
			return err
		}
		return s.send(map[string]any{"v": 1, "type": "challenge_canceled", "challengeId": challengeID})
	case "challengeDeclined":
		challengeID, err := objectID(payload.Challenge)
		if err != nil {
			return err
		}
		return s.send(map[string]any{"v": 1, "type": "challenge_declined", "challengeId": challengeID})
	case "gameStart":
		game, err := normalizeGameReference(payload.Game)
		if err != nil {
			return err
		}
		return s.send(map[string]any{"v": 1, "type": "game_start", "game": game})
	case "gameFinish":
		game, err := normalizeGameReference(payload.Game)
		if err != nil {
			return err
		}
		return s.send(map[string]any{"v": 1, "type": "game_finish", "game": game})
	default:
		return nil
	}
}

func (s *Session) openGame(gameID string) {
	s.mutex.Lock()
	if s.gameCancel != nil {
		s.gameCancel()
	}
	gameContext, cancel := context.WithCancel(s.context)
	s.gameCancel = cancel
	s.gameID = gameID
	s.mutex.Unlock()
	s.wait.Add(1)
	go func() {
		defer s.wait.Done()
		err := s.runGameStream(gameContext, gameID)
		if err != nil && !errors.Is(err, context.Canceled) {
			_ = s.sendAPIError(err, "", true)
		}
	}()
}

func (s *Session) closeGame(gameID string) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if s.gameID == gameID && s.gameCancel != nil {
		s.gameCancel()
		s.gameCancel = nil
		s.gameID = ""
	}
}

func (s *Session) runGameStream(ctx context.Context, gameID string) error {
	terminal := false
	err := reconnect.Run(ctx, s.policy, func(operationContext context.Context) error {
		terminal = false
		err := s.api.StreamGame(operationContext, gameID, func(event lichess.RawEvent) error {
			isTerminal, err := s.handleGameEvent(gameID, event)
			terminal = terminal || isTerminal
			return err
		})
		if errors.Is(err, io.EOF) && terminal {
			return nil
		}
		return err
	}, retryDecision, func(attempt int, delay time.Duration, _ error) {
		s.notifyReconnect("game", attempt, delay)
	})
	return err
}

func (s *Session) handleGameEvent(gameID string, event lichess.RawEvent) (bool, error) {
	switch event.Type {
	case "gameFull":
		state, terminal, err := s.normalizeGameFull(event.JSON)
		if err != nil {
			return false, err
		}
		return terminal, s.send(map[string]any{
			"v": 1, "type": "game_full", "gameId": gameID, "state": state,
		})
	case "gameState":
		state, terminal, err := normalizeGameState(event.JSON)
		if err != nil {
			return false, err
		}
		return terminal, s.send(map[string]any{
			"v": 1, "type": "game_state", "gameId": gameID, "state": state,
		})
	case "opponentGone":
		var gone struct {
			Gone              bool `json:"gone"`
			ClaimWinInSeconds int  `json:"claimWinInSeconds,omitempty"`
		}
		if err := json.Unmarshal(event.JSON, &gone); err != nil {
			return false, &lichess.APIError{Code: "invalid_json"}
		}
		return false, s.send(map[string]any{
			"v": 1, "type": "opponent_gone", "gameId": gameID,
			"gone": gone.Gone, "claimWinInSeconds": gone.ClaimWinInSeconds,
		})
	default:
		return false, nil
	}
}

func (s *Session) mutate(ctx context.Context, command protocol.Command) error {
	s.mutationMutex.Lock()
	defer s.mutationMutex.Unlock()
	if cached := s.cached(command.RequestID); cached != nil {
		return s.send(cached)
	}
	if !s.connected() {
		result := errorCodeMessage("not_connected", command.RequestID, false)
		s.remember(command.RequestID, result)
		return s.send(result)
	}

	var operation func(context.Context) error
	switch command.Type {
	case "accept_challenge":
		operation = func(ctx context.Context) error {
			return s.api.AcceptChallenge(ctx, command.ChallengeID)
		}
	case "decline_challenge":
		operation = func(ctx context.Context) error {
			return s.api.DeclineChallenge(ctx, command.ChallengeID, command.Reason)
		}
	case "seek":
		operation = func(ctx context.Context) error {
			return s.api.CreateSeek(ctx, lichess.SeekOptions{
				Rated: command.Rated, TimeControl: command.TimeControl,
			})
		}
	case "cancel_seek":
		operation = func(ctx context.Context) error {
			return s.api.CancelSeek(ctx)
		}
	case "move":
		operation = func(ctx context.Context) error {
			return s.api.Move(ctx, command.GameID, command.Move)
		}
	case "offer_draw", "accept_draw":
		operation = func(ctx context.Context) error {
			return s.api.Draw(ctx, command.GameID, true)
		}
	case "decline_draw":
		operation = func(ctx context.Context) error {
			return s.api.Draw(ctx, command.GameID, false)
		}
	case "resign":
		operation = func(ctx context.Context) error {
			return s.api.Resign(ctx, command.GameID)
		}
	case "abort":
		operation = func(ctx context.Context) error {
			return s.api.Abort(ctx, command.GameID)
		}
	}
	var err error
	if operation == nil {
		err = errors.New("unknown mutation")
	} else {
		err = s.runRequest(ctx, operation)
	}

	result := map[string]any{
		"v": 1, "type": "command_ok", "requestId": command.RequestID, "command": command.Type,
	}
	if err != nil {
		var apiError *lichess.APIError
		if command.Type == "move" && errors.As(err, &apiError) && apiError.Code == "lichess_rejected" {
			result = map[string]any{
				"v": 1, "type": "move_rejected", "requestId": command.RequestID,
				"gameId": command.GameID, "move": command.Move, "reason": "lichess_rejected",
			}
		} else {
			result = errorMessage(err, command.RequestID, false)
		}
	}
	s.remember(command.RequestID, result)
	return s.send(result)
}

func (s *Session) runRequest(ctx context.Context, operation func(context.Context) error) error {
	var err error
	for attempt := 0; attempt < maxRequestAttempts; attempt++ {
		err = operation(ctx)
		if err == nil {
			return nil
		}
		retry, hint := requestRetryDecision(err)
		if !retry || attempt+1 == maxRequestAttempts {
			return err
		}
		if sleepErr := s.policy.Sleep(ctx, s.policy.Delay(attempt, hint)); sleepErr != nil {
			return sleepErr
		}
	}
	return err
}

func requestRetryDecision(err error) (bool, time.Duration) {
	if errors.Is(err, context.DeadlineExceeded) {
		return true, 0
	}
	var apiError *lichess.APIError
	if errors.As(err, &apiError) {
		switch apiError.Code {
		case "network_error", "http_error":
			return true, 0
		}
	}
	return false, 0
}

func (s *Session) cached(requestID string) map[string]any {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.results[requestID]
}

func (s *Session) connected() bool {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	return s.account != nil
}

func (s *Session) remember(requestID string, result map[string]any) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if _, exists := s.results[requestID]; exists {
		return
	}
	if len(s.resultOrder) == 128 {
		delete(s.results, s.resultOrder[0])
		s.resultOrder = s.resultOrder[1:]
	}
	s.results[requestID] = result
	s.resultOrder = append(s.resultOrder, requestID)
}

func (s *Session) notifyReconnect(name string, attempt int, delay time.Duration) {
	seconds := int(math.Ceil(delay.Seconds()))
	_ = s.send(map[string]any{
		"v": 1, "type": "disconnected", "reason": name + "_stream_interrupted", "retryIn": seconds,
	})
	_ = s.send(map[string]any{
		"v": 1, "type": "reconnecting", "stream": name, "attempt": attempt, "retryIn": seconds,
	})
}

func (s *Session) send(message map[string]any) error {
	return s.connection.Send(message)
}

func (s *Session) sendAPIError(err error, requestID string, fatal bool) error {
	return s.send(errorMessage(err, requestID, fatal))
}

func errorMessage(err error, requestID string, fatal bool) map[string]any {
	code := "internal"
	var apiError *lichess.APIError
	if errors.As(err, &apiError) {
		code = apiError.Code
	} else if errors.Is(err, context.DeadlineExceeded) {
		code = "network_timeout"
	} else if errors.Is(err, stream.ErrMessageTooLarge) {
		code = "message_too_large"
	}
	return errorCodeMessage(code, requestID, fatal)
}

func errorCodeMessage(code, requestID string, fatal bool) map[string]any {
	message := map[string]any{
		"v": 1, "type": "error", "code": code, "message": "Bridge request failed", "fatal": fatal,
	}
	if requestID != "" {
		message["requestId"] = requestID
	}
	return message
}

func retryDecision(err error) (bool, time.Duration) {
	if errors.Is(err, context.DeadlineExceeded) {
		return true, 0
	}
	if errors.Is(err, io.EOF) || errors.Is(err, stream.ErrTruncatedLine) {
		return true, 0
	}
	var apiError *lichess.APIError
	if errors.As(err, &apiError) {
		switch apiError.Code {
		case "network_error", "http_error", "rate_limited":
			return true, apiError.RetryAfter
		}
	}
	return false, 0
}
