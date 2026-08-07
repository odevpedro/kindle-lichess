// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package lichess

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/odevpedro/kindle-lichess/bridge/internal/auth"
)

func newTestClient(t *testing.T, handler http.Handler, token string) (*Client, *httptest.Server) {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	path := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(path, []byte(token), 0o600); err != nil {
		t.Fatal(err)
	}
	loadedToken, err := auth.LoadToken(path)
	if err != nil {
		t.Fatal(err)
	}
	client, err := NewClient(server.URL, server.Client(), loadedToken)
	if err != nil {
		t.Fatal(err)
	}
	return client, server
}

func TestAccountUsesBearerAndParsesResponse(t *testing.T) {
	t.Parallel()
	canary := "runtime-canary-not-a-real-token"
	client, _ := newTestClient(t, http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet || request.URL.Path != "/api/account" {
			t.Fatalf("request = %s %s", request.Method, request.URL.Path)
		}
		if got := request.Header.Get("Authorization"); got != "Bearer "+canary {
			t.Fatalf("authorization = %q", got)
		}
		_, _ = io.WriteString(writer, `{"id":"kindletester","username":"KindleTester"}`)
	}), canary)
	account, err := client.Account(context.Background())
	if err != nil || account.ID != "kindletester" || account.Username != "KindleTester" {
		t.Fatalf("account = %#v, %v", account, err)
	}
}

func TestStreamsSkipKeepaliveAndParseMultipleEvents(t *testing.T) {
	t.Parallel()
	client, _ := newTestClient(t, http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "application/x-ndjson")
		flusher := writer.(http.Flusher)
		_, _ = io.WriteString(writer, "\n"+`{"type":"challenge","challenge":{"id":"c1"}}`[:17])
		flusher.Flush()
		_, _ = io.WriteString(writer, `{"type":"challenge","challenge":{"id":"c1"}}`[17:]+"\n"+
			`{"type":"gameStart","game":{"id":"g1"}}`+"\n")
	}), "test")
	var types []string
	err := client.StreamAccount(context.Background(), func(event RawEvent) error {
		types = append(types, event.Type)
		return nil
	})
	if !errors.Is(err, io.EOF) {
		t.Fatalf("stream error = %v", err)
	}
	if !reflect.DeepEqual(types, []string{"challenge", "gameStart"}) {
		t.Fatalf("types = %v", types)
	}
}

func TestEveryBoardMutationUsesDocumentedEndpoint(t *testing.T) {
	t.Parallel()
	type requestRecord struct{ method, path, form string }
	var mutex sync.Mutex
	var records []requestRecord
	client, _ := newTestClient(t, http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		content, _ := io.ReadAll(request.Body)
		mutex.Lock()
		records = append(records, requestRecord{request.Method, request.URL.Path, string(content)})
		mutex.Unlock()
		writer.WriteHeader(http.StatusOK)
	}), "test")
	ctx := context.Background()
	operations := []func() error{
		func() error { return client.AcceptChallenge(ctx, "c1") },
		func() error { return client.DeclineChallenge(ctx, "c1", "generic") },
		func() error { return client.Move(ctx, "g1", "e2e4") },
		func() error { return client.Draw(ctx, "g1", true) },
		func() error { return client.Draw(ctx, "g1", false) },
		func() error { return client.Resign(ctx, "g1") },
		func() error { return client.Abort(ctx, "g1") },
	}
	for _, operation := range operations {
		if err := operation(); err != nil {
			t.Fatal(err)
		}
	}
	want := []requestRecord{
		{"POST", "/api/challenge/c1/accept", ""},
		{"POST", "/api/challenge/c1/decline", "reason=generic"},
		{"POST", "/api/board/game/g1/move/e2e4", ""},
		{"POST", "/api/board/game/g1/draw/yes", ""},
		{"POST", "/api/board/game/g1/draw/no", ""},
		{"POST", "/api/board/game/g1/resign", ""},
		{"POST", "/api/board/game/g1/abort", ""},
	}
	if !reflect.DeepEqual(records, want) {
		t.Fatalf("records = %#v, want %#v", records, want)
	}
}

func TestHTTPErrorMappingRetryAfterAndNoSecretLeak(t *testing.T) {
	t.Parallel()
	canary := "never-print-this-canary"
	tests := []struct {
		status int
		code   string
	}{
		{400, "lichess_rejected"}, {401, "auth_unauthorized"}, {403, "auth_forbidden"},
		{404, "not_found"}, {429, "rate_limited"}, {500, "http_error"},
	}
	for _, test := range tests {
		t.Run(fmt.Sprint(test.status), func(t *testing.T) {
			client, _ := newTestClient(t, http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
				writer.Header().Set("Retry-After", "7")
				writer.WriteHeader(test.status)
				_, _ = io.WriteString(writer, canary)
			}), canary)
			err := client.Move(context.Background(), "g1", "e2e4")
			var apiError *APIError
			if !errors.As(err, &apiError) || apiError.Code != test.code {
				t.Fatalf("error = %#v", err)
			}
			if apiError.RetryAfter != 7*time.Second {
				t.Fatalf("retry after = %v", apiError.RetryAfter)
			}
			if strings.Contains(err.Error(), canary) || strings.Contains(fmt.Sprintf("%v", client), canary) {
				t.Fatal("secret leaked into error or client formatting")
			}
		})
	}
}

func TestRetryAfterHTTPDate(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, time.August, 6, 12, 0, 0, 0, time.UTC)
	if got := parseRetryAfter(now.Add(13*time.Second).Format(http.TimeFormat), now); got != 13*time.Second {
		t.Fatalf("retry after date = %v", got)
	}
	if got := parseRetryAfter("invalid", now); got != 0 {
		t.Fatalf("invalid retry after = %v", got)
	}
}

func TestStreamReadInterruptionIsRetryable(t *testing.T) {
	t.Parallel()
	client, _ := newTestClient(t, http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writer.Header().Set("Content-Type", "application/x-ndjson")
		hijacker, ok := writer.(http.Hijacker)
		if !ok {
			t.Fatal("server does not support hijacking")
		}
		connection, buffered, err := hijacker.Hijack()
		if err != nil {
			t.Fatal(err)
		}
		_, _ = buffered.WriteString(`{"type":"gameState","moves":`)
		_ = buffered.Flush()
		_ = connection.Close()
	}), "test")
	var apiError *APIError
	err := client.StreamGame(context.Background(), "g1", func(RawEvent) error { return nil })
	if !errors.As(err, &apiError) || apiError.Code != "network_error" {
		t.Fatalf("error = %v (want retryable network_error)", err)
	}
}

func TestContextCancellationClosesStream(t *testing.T) {
	t.Parallel()
	requestStarted := make(chan struct{})
	requestCanceled := make(chan struct{})
	client, _ := newTestClient(t, http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "application/x-ndjson")
		writer.WriteHeader(http.StatusOK)
		writer.(http.Flusher).Flush()
		close(requestStarted)
		<-request.Context().Done()
		close(requestCanceled)
	}), "test")
	ctx, cancel := context.WithCancel(context.Background())
	result := make(chan error, 1)
	go func() { result <- client.StreamAccount(ctx, func(RawEvent) error { return nil }) }()
	<-requestStarted
	cancel()
	if err := <-result; !errors.Is(err, context.Canceled) {
		t.Fatalf("stream error = %v", err)
	}
	select {
	case <-requestCanceled:
	case <-time.After(time.Second):
		t.Fatal("server did not observe request cancellation")
	}
}

func TestTimeoutAndInvalidStreamJSON(t *testing.T) {
	t.Parallel()
	t.Run("timeout", func(t *testing.T) {
		client, _ := newTestClient(t, http.HandlerFunc(func(_ http.ResponseWriter, request *http.Request) {
			<-request.Context().Done()
		}), "test")
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
		defer cancel()
		if err := client.StreamAccount(ctx, func(RawEvent) error { return nil }); !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("error = %v", err)
		}
	})
	t.Run("invalid json", func(t *testing.T) {
		client, _ := newTestClient(t, http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
			_, _ = io.WriteString(writer, "not-json\n")
		}), "test")
		var apiError *APIError
		err := client.StreamAccount(context.Background(), func(RawEvent) error { return nil })
		if !errors.As(err, &apiError) || apiError.Code != "invalid_json" {
			t.Fatalf("error = %v", err)
		}
	})
}

func TestClientRejectsInvalidBaseURL(t *testing.T) {
	t.Parallel()
	if _, err := NewClient(":bad", nil, auth.Token{}); err == nil {
		t.Fatal("invalid URL accepted")
	}
	if _, err := url.Parse(":bad"); err == nil {
		t.Fatal("test precondition failed")
	}
}
