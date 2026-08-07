// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package app

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/odevpedro/kindle-lichess/bridge/internal/auth"
	"github.com/odevpedro/kindle-lichess/bridge/internal/ipc"
	"github.com/odevpedro/kindle-lichess/bridge/internal/lichess"
	"github.com/odevpedro/kindle-lichess/bridge/internal/reconnect"
	"github.com/odevpedro/kindle-lichess/bridge/internal/stream"
)

const challengeEvent = `{"type":"challenge","challenge":{"id":"c1","direction":"in","status":"created","rated":false,"speed":"rapid","variant":{"key":"standard"},"color":"white","challenger":{"id":"opponent","name":"Opponent","rating":1500},"timeControl":{"type":"clock","limit":600,"increment":5}}}`
const gameFullEvent = `{"type":"gameFull","id":"g1","variant":{"key":"standard"},"speed":"rapid","rated":false,"createdAt":1,"white":{"id":"kindletester","name":"KindleTester","rating":1500},"black":{"id":"opponent","name":"Opponent","rating":1500},"initialFen":"startpos","state":{"type":"gameState","moves":"","wtime":600000,"btime":600000,"winc":5000,"binc":5000,"status":"started"}}`

type fakeLichess struct {
	server         *httptest.Server
	accountEvents  chan string
	gameEvents     chan string
	mutex          sync.Mutex
	requests       map[string]int
	acceptFailures int
}

func newFakeLichess(t *testing.T) *fakeLichess {
	t.Helper()
	fake := &fakeLichess{
		accountEvents: make(chan string, 16),
		gameEvents:    make(chan string, 16),
		requests:      make(map[string]int),
	}
	fake.server = httptest.NewServer(http.HandlerFunc(fake.handle))
	t.Cleanup(fake.server.Close)
	return fake
}

func (f *fakeLichess) record(path string) {
	f.mutex.Lock()
	defer f.mutex.Unlock()
	f.requests[path]++
}

func (f *fakeLichess) count(path string) int {
	f.mutex.Lock()
	defer f.mutex.Unlock()
	return f.requests[path]
}

func (f *fakeLichess) handle(writer http.ResponseWriter, request *http.Request) {
	f.record(request.URL.Path)
	if request.Header.Get("Authorization") != "Bearer integration-canary" {
		writer.WriteHeader(http.StatusUnauthorized)
		return
	}
	switch request.URL.Path {
	case "/api/account":
		_, _ = io.WriteString(writer, `{"id":"kindletester","username":"KindleTester"}`)
	case "/api/stream/event":
		f.writeStream(writer, request, challengeEvent, f.accountEvents)
	case "/api/challenge/c1/accept":
		if f.count(request.URL.Path) <= f.acceptFailures {
			writer.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		writer.WriteHeader(http.StatusOK)
		f.accountEvents <- `{"type":"gameStart","game":{"id":"g1","color":"white"}}`
	case "/api/board/game/stream/g1":
		f.writeStream(writer, request, gameFullEvent, f.gameEvents)
	case "/api/board/game/g1/move/e2e4":
		writer.WriteHeader(http.StatusOK)
		f.gameEvents <- `{"type":"gameState","moves":"e2e4","wtime":599000,"btime":600000,"winc":5000,"binc":5000,"status":"started"}`
		f.gameEvents <- `{"type":"gameState","moves":"e2e4 e7e5","wtime":599000,"btime":598800,"winc":5000,"binc":5000,"status":"started"}`
	case "/api/board/game/g1/move/a1a8":
		writer.WriteHeader(http.StatusBadRequest)
	case "/api/board/game/g1/draw/yes":
		writer.WriteHeader(http.StatusOK)
		f.gameEvents <- `{"type":"gameState","moves":"e2e4 e7e5","wtime":599000,"btime":598800,"winc":5000,"binc":5000,"status":"draw"}`
		f.accountEvents <- `{"type":"gameFinish","game":{"id":"g1","status":"draw"}}`
	default:
		writer.WriteHeader(http.StatusNotFound)
	}
}

func (f *fakeLichess) writeStream(writer http.ResponseWriter, request *http.Request,
	initial string, events <-chan string) {
	writer.Header().Set("Content-Type", "application/x-ndjson")
	flusher := writer.(http.Flusher)
	_, _ = io.WriteString(writer, initial+"\n\n")
	flusher.Flush()
	for {
		select {
		case event := <-events:
			_, _ = io.WriteString(writer, event+"\n")
			flusher.Flush()
		case <-request.Context().Done():
			return
		}
	}
}

func testAPI(t *testing.T, fake *fakeLichess) *lichess.Client {
	t.Helper()
	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("integration-canary"), 0o600); err != nil {
		t.Fatal(err)
	}
	token, err := auth.LoadToken(tokenPath)
	if err != nil {
		t.Fatal(err)
	}
	client, err := lichess.NewClient(fake.server.URL, fake.server.Client(), token)
	if err != nil {
		t.Fatal(err)
	}
	return client
}

type pluginClient struct {
	connection net.Conn
	reader     *stream.Reader
	writer     *stream.Writer
}

func newPluginClient(t *testing.T, path string) *pluginClient {
	t.Helper()
	connection, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	if err := connection.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		t.Fatal(err)
	}
	return &pluginClient{
		connection: connection,
		reader:     stream.NewReader(connection, stream.DefaultMaxMessageBytes),
		writer:     stream.NewWriter(connection, stream.DefaultMaxMessageBytes),
	}
}

func (p *pluginClient) send(t *testing.T, message map[string]any) {
	t.Helper()
	if err := p.writer.Write(message); err != nil {
		t.Fatal(err)
	}
}

func (p *pluginClient) read(t *testing.T) map[string]any {
	t.Helper()
	line, err := p.reader.Next()
	if err != nil {
		t.Fatal(err)
	}
	var message map[string]any
	if err := json.Unmarshal(line, &message); err != nil {
		t.Fatal(err)
	}
	return message
}

func (p *pluginClient) until(t *testing.T, wanted ...string) map[string]map[string]any {
	t.Helper()
	remaining := make(map[string]bool, len(wanted))
	for _, kind := range wanted {
		remaining[kind] = true
	}
	result := make(map[string]map[string]any, len(wanted))
	for len(remaining) > 0 {
		message := p.read(t)
		kind, _ := message["type"].(string)
		if remaining[kind] {
			result[kind] = message
			delete(remaining, kind)
		}
	}
	return result
}

func immediatePolicy() reconnect.Policy {
	return reconnect.Policy{
		Base: time.Millisecond,
		Max:  time.Millisecond,
		Sleep: func(ctx context.Context, _ time.Duration) error {
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
				return nil
			}
		},
	}
}

func TestEndToEndUnixBridgeAgainstFakeLichess(t *testing.T) {
	fake := newFakeLichess(t)
	socket := filepath.Join(t.TempDir(), "kindle-lichess.sock")
	server, err := ipc.Listen(socket)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	api := testAPI(t, fake)
	serveResult := make(chan error, 1)
	go func() {
		serveResult <- server.Serve(ctx, func(ctx context.Context, connection net.Conn) error {
			return NewSession(api, immediatePolicy()).Run(ctx, connection)
		})
	}()

	plugin := newPluginClient(t, socket)
	defer plugin.connection.Close()
	plugin.send(t, map[string]any{"v": 1, "type": "open_game", "gameId": "g1"})
	notConnected := plugin.until(t, "error")["error"]
	if notConnected["code"] != "not_connected" {
		t.Fatalf("open before connect = %#v", notConnected)
	}
	plugin.send(t, map[string]any{
		"v": 1, "type": "accept_challenge", "requestId": "r-before", "challengeId": "c1",
	})
	notConnected = plugin.until(t, "error")["error"]
	if notConnected["code"] != "not_connected" ||
		fake.count("/api/challenge/c1/accept") != 0 {
		t.Fatalf("mutation before connect = %#v, HTTP count=%d", notConnected,
			fake.count("/api/challenge/c1/accept"))
	}
	plugin.send(t, map[string]any{"v": 1, "type": "connect"})
	connectedAndChallenge := plugin.until(t, "connected", "challenge")
	account := connectedAndChallenge["connected"]["account"].(map[string]any)
	if account["username"] != "KindleTester" {
		t.Fatalf("account = %#v", account)
	}

	fake.acceptFailures = 2
	plugin.send(t, map[string]any{
		"v": 1, "type": "accept_challenge", "requestId": "r1", "challengeId": "c1",
	})
	plugin.until(t, "command_ok", "game_start")
	if calls := fake.count("/api/challenge/c1/accept"); calls != 3 {
		t.Fatalf("transient accept attempts = %d, want 3", calls)
	}
	plugin.send(t, map[string]any{"v": 1, "type": "open_game", "gameId": "g1"})
	gameFull := plugin.until(t, "game_full")["game_full"]
	fullState := gameFull["state"].(map[string]any)
	if fullState["color"] != "w" || fullState["variant"] != "standard" || fullState["initialFen"] != "startpos" {
		t.Fatalf("gameFull state = %#v", fullState)
	}

	move := map[string]any{
		"v": 1, "type": "move", "requestId": "r2", "gameId": "g1", "move": "e2e4",
	}
	plugin.send(t, move)
	var finalMoves string
	var commandOK bool
	for !commandOK || finalMoves != "e2e4 e7e5" {
		message := plugin.read(t)
		switch message["type"] {
		case "command_ok":
			commandOK = message["requestId"] == "r2"
		case "game_state":
			state := message["state"].(map[string]any)
			finalMoves, _ = state["moves"].(string)
		}
	}
	plugin.send(t, move)
	duplicate := plugin.until(t, "command_ok")["command_ok"]
	if duplicate["requestId"] != "r2" || fake.count("/api/board/game/g1/move/e2e4") != 1 {
		t.Fatalf("duplicate result = %#v, HTTP count=%d", duplicate,
			fake.count("/api/board/game/g1/move/e2e4"))
	}

	plugin.send(t, map[string]any{
		"v": 1, "type": "move", "requestId": "r-reject", "gameId": "g1", "move": "a1a8",
	})
	rejected := plugin.until(t, "move_rejected")["move_rejected"]
	if rejected["reason"] != "lichess_rejected" {
		t.Fatalf("rejection = %#v", rejected)
	}

	plugin.send(t, map[string]any{
		"v": 1, "type": "offer_draw", "requestId": "r3", "gameId": "g1",
	})
	finished := plugin.until(t, "command_ok", "game_state", "game_finish")
	finishGame := finished["game_finish"]["game"].(map[string]any)
	if finishGame["status"] != "draw" {
		t.Fatalf("game finish = %#v", finishGame)
	}

	plugin.send(t, map[string]any{"v": 1, "type": "disconnect"})
	if message := plugin.until(t, "disconnected")["disconnected"]; message["reason"] != "closed_by_plugin" {
		t.Fatalf("disconnect = %#v", message)
	}
	if err := <-serveResult; err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(socket); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains after bridge exit: %v", err)
	}
}

func TestAccountStreamReconnectsAfterEOF(t *testing.T) {
	var mutex sync.Mutex
	streamCalls := 0
	secondConnected := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/api/account":
			_, _ = io.WriteString(writer, `{"id":"kindletester","username":"KindleTester"}`)
		case "/api/stream/event":
			mutex.Lock()
			streamCalls++
			call := streamCalls
			mutex.Unlock()
			_, _ = io.WriteString(writer, challengeEvent+"\n")
			writer.(http.Flusher).Flush()
			if call == 1 {
				return
			}
			close(secondConnected)
			<-request.Context().Done()
		default:
			writer.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	tokenPath := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenPath, []byte("test"), 0o600); err != nil {
		t.Fatal(err)
	}
	token, _ := auth.LoadToken(tokenPath)
	client, _ := lichess.NewClient(server.URL, server.Client(), token)
	serverSide, pluginSide := net.Pipe()
	ctx, cancel := context.WithCancel(context.Background())
	result := make(chan error, 1)
	go func() { result <- NewSession(client, immediatePolicy()).Run(ctx, serverSide) }()
	plugin := &pluginClient{
		connection: pluginSide,
		reader:     stream.NewReader(pluginSide, stream.DefaultMaxMessageBytes),
		writer:     stream.NewWriter(pluginSide, stream.DefaultMaxMessageBytes),
	}
	_ = pluginSide.SetDeadline(time.Now().Add(5 * time.Second))
	plugin.send(t, map[string]any{"v": 1, "type": "connect"})
	seen := plugin.until(t, "connected", "challenge", "disconnected", "reconnecting")
	if seen["reconnecting"]["stream"] != "account" {
		t.Fatalf("reconnect = %#v", seen["reconnecting"])
	}
	select {
	case <-secondConnected:
	case <-time.After(time.Second):
		t.Fatal("account stream was not reopened")
	}
	cancel()
	_ = pluginSide.Close()
	if err := <-result; !errors.Is(err, context.Canceled) && err != nil {
		t.Fatal(err)
	}
	mutex.Lock()
	defer mutex.Unlock()
	if streamCalls != 2 {
		t.Fatalf("stream calls = %d", streamCalls)
	}
}

func TestErrorMessagesNeverContainUnderlyingText(t *testing.T) {
	message := errorMessage(errors.New("secret-like upstream body"), "r1", false)
	encoded, _ := json.Marshal(message)
	if strings.Contains(string(encoded), "secret-like") {
		t.Fatalf("error leaked underlying text: %s", encoded)
	}
}

func TestRetryDecisionsIncludeTimeout(t *testing.T) {
	decisions := []struct {
		name     string
		decision func(error) (bool, time.Duration)
	}{
		{"stream", retryDecision},
		{"mutation", mutationRetryDecision},
	}
	for _, test := range decisions {
		retry, delay := test.decision(context.DeadlineExceeded)
		if !retry || delay != 0 {
			t.Fatalf("%s timeout retry = %v, delay = %v", test.name, retry, delay)
		}
	}
}
