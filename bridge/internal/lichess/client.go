// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package lichess

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/odevpedro/kindle-lichess/bridge/internal/auth"
	"github.com/odevpedro/kindle-lichess/bridge/internal/stream"
)

const maxJSONResponseBytes = 65_536

type Client struct {
	baseURL    *url.URL
	httpClient *http.Client
	token      auth.Token
	now        func() time.Time
}

func NewClient(baseURL string, httpClient *http.Client, token auth.Token) (*Client, error) {
	parsed, err := url.Parse(baseURL)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return nil, errors.New("invalid_base_url")
	}
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &Client{baseURL: parsed, httpClient: httpClient, token: token, now: time.Now}, nil
}

func (*Client) String() string { return "lichess.Client{<redacted>}" }

type Account struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Title    string `json:"title,omitempty"`
}

type RawEvent struct {
	Type string
	JSON json.RawMessage
}

type APIError struct {
	Code       string
	StatusCode int
	RetryAfter time.Duration
}

func (e *APIError) Error() string {
	if e.StatusCode > 0 {
		return fmt.Sprintf("%s (HTTP %d)", e.Code, e.StatusCode)
	}
	return e.Code
}

func (c *Client) Account(ctx context.Context) (Account, error) {
	response, err := c.do(ctx, http.MethodGet, "/api/account", nil, "")
	if err != nil {
		return Account{}, err
	}
	defer response.Body.Close()
	if err := c.responseError(response); err != nil {
		return Account{}, err
	}
	limited := io.LimitReader(response.Body, maxJSONResponseBytes+1)
	content, err := io.ReadAll(limited)
	if err != nil {
		return Account{}, transportError(err)
	}
	if len(content) > maxJSONResponseBytes {
		return Account{}, &APIError{Code: "message_too_large"}
	}
	var account Account
	if err := json.Unmarshal(content, &account); err != nil || account.ID == "" || account.Username == "" {
		return Account{}, &APIError{Code: "invalid_response"}
	}
	return account, nil
}

func (c *Client) StreamAccount(ctx context.Context, handler func(RawEvent) error) error {
	return c.stream(ctx, "/api/stream/event", handler)
}

func (c *Client) StreamGame(ctx context.Context, gameID string, handler func(RawEvent) error) error {
	return c.stream(ctx, "/api/board/game/stream/"+url.PathEscape(gameID), handler)
}

func (c *Client) stream(ctx context.Context, path string, handler func(RawEvent) error) error {
	response, err := c.do(ctx, http.MethodGet, path, nil, "")
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if err := c.responseError(response); err != nil {
		return err
	}
	reader := stream.NewReader(response.Body, stream.DefaultMaxMessageBytes)
	for {
		line, err := reader.Next()
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if errors.Is(err, io.EOF) ||
				errors.Is(err, stream.ErrTruncatedLine) ||
				errors.Is(err, stream.ErrMessageTooLarge) {
				return err
			}
			return transportError(err)
		}
		var envelope struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(line, &envelope); err != nil || envelope.Type == "" {
			return &APIError{Code: "invalid_json"}
		}
		if err := handler(RawEvent{Type: envelope.Type, JSON: bytes.Clone(line)}); err != nil {
			return err
		}
	}
}

func (c *Client) AcceptChallenge(ctx context.Context, challengeID string) error {
	return c.mutate(ctx, "/api/challenge/"+url.PathEscape(challengeID)+"/accept", "")
}

func (c *Client) DeclineChallenge(ctx context.Context, challengeID, reason string) error {
	values := url.Values{}
	if reason != "" {
		values.Set("reason", reason)
	}
	return c.mutate(ctx, "/api/challenge/"+url.PathEscape(challengeID)+"/decline", values.Encode())
}

type SeekOptions struct {
	Rated       bool
	TimeControl string
}

// CreateSeek registers a seek on the Lichess automatic seeker; when an opponent of
// similar rating appears the event stream emits a gameStart. Rated games require a
// time control; casual unlimited games are expressed with the special "0+1" marker.
func (c *Client) CreateSeek(ctx context.Context, options SeekOptions) error {
	values := url.Values{}
	if options.Rated {
		values.Set("rated", "true")
	} else {
		values.Set("rated", "false")
	}
	if options.TimeControl != "" {
		values.Set("timeControl", options.TimeControl)
	}
	values.Set("variant", "standard")
	values.Set("color", "random")
	values.Set("keepAliveStream", "true")
	return c.mutate(ctx, "/api/board/seek", values.Encode())
}

func (c *Client) CancelSeek(ctx context.Context) error {
	return c.mutate(ctx, "/api/board/seek/cancel", "")
}

func (c *Client) Move(ctx context.Context, gameID, move string) error {
	return c.mutate(ctx, "/api/board/game/"+url.PathEscape(gameID)+"/move/"+url.PathEscape(move), "")
}

func (c *Client) Draw(ctx context.Context, gameID string, accept bool) error {
	answer := "no"
	if accept {
		answer = "yes"
	}
	return c.mutate(ctx, "/api/board/game/"+url.PathEscape(gameID)+"/draw/"+answer, "")
}

func (c *Client) Resign(ctx context.Context, gameID string) error {
	return c.mutate(ctx, "/api/board/game/"+url.PathEscape(gameID)+"/resign", "")
}

func (c *Client) Abort(ctx context.Context, gameID string) error {
	return c.mutate(ctx, "/api/board/game/"+url.PathEscape(gameID)+"/abort", "")
}

func (c *Client) mutate(ctx context.Context, path, encodedForm string) error {
	var body io.Reader
	contentType := ""
	if encodedForm != "" {
		body = strings.NewReader(encodedForm)
		contentType = "application/x-www-form-urlencoded"
	}
	response, err := c.do(ctx, http.MethodPost, path, body, contentType)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	return c.responseError(response)
}

func (c *Client) do(ctx context.Context, method, path string, body io.Reader, contentType string) (*http.Response, error) {
	reference := &url.URL{Path: path}
	endpoint := c.baseURL.ResolveReference(reference)
	request, err := http.NewRequestWithContext(ctx, method, endpoint.String(), body)
	if err != nil {
		return nil, &APIError{Code: "internal"}
	}
	request.Header.Set("Accept", "application/x-ndjson, application/json")
	request.Header.Set("User-Agent", "kindle-lichess-bridge/phase2")
	if contentType != "" {
		request.Header.Set("Content-Type", contentType)
	}
	if !c.token.Empty() {
		request.Header.Set("Authorization", "Bearer "+c.token.Bearer())
	}
	response, err := c.httpClient.Do(request)
	if err != nil {
		return nil, transportError(err)
	}
	return response, nil
}

func (c *Client) responseError(response *http.Response) error {
	if response.StatusCode >= 200 && response.StatusCode < 300 {
		return nil
	}
	code := "http_error"
	switch response.StatusCode {
	case http.StatusBadRequest:
		code = "lichess_rejected"
	case http.StatusUnauthorized:
		code = "auth_unauthorized"
	case http.StatusForbidden:
		code = "auth_forbidden"
	case http.StatusNotFound:
		code = "not_found"
	case http.StatusTooManyRequests:
		code = "rate_limited"
	}
	return &APIError{
		Code: code, StatusCode: response.StatusCode,
		RetryAfter: parseRetryAfter(response.Header.Get("Retry-After"), c.now()),
	}
}

func parseRetryAfter(value string, now time.Time) time.Duration {
	value = strings.TrimSpace(value)
	if seconds, err := strconv.ParseInt(value, 10, 32); err == nil && seconds >= 0 {
		return time.Duration(seconds) * time.Second
	}
	if date, err := http.ParseTime(value); err == nil && date.After(now) {
		return date.Sub(now)
	}
	return 0
}

func transportError(err error) error {
	if errors.Is(err, context.Canceled) {
		return context.Canceled
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return context.DeadlineExceeded
	}
	return &APIError{Code: "network_error"}
}
