// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package app

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	"github.com/odevpedro/kindle-lichess/bridge/internal/lichess"
)

func TestRejectedEventLogContainsOnlyAllowlistedMetadata(t *testing.T) {
	const canary = "private-user-game-token-canary"
	event := lichess.RawEvent{
		Type: "gameFull",
		JSON: []byte(`{"id":"` + canary + `","white":{"name":"` + canary + `"}}`),
	}
	var output bytes.Buffer
	writeRejectedEvent(&output, event, &lichess.APIError{Code: "invalid_response"})
	if output.String() !=
		"kindle-lichess-bridge: normalize_reject event=gameFull code=invalid_response\n" {
		t.Fatalf("diagnostic output = %q", output.String())
	}
	if strings.Contains(output.String(), canary) {
		t.Fatalf("diagnostic output leaked private payload: %q", output.String())
	}
}

func TestRejectedEventLogSanitizesUnknownTypeAndError(t *testing.T) {
	const canary = "private-control-value"
	var output bytes.Buffer
	writeRejectedEvent(&output, lichess.RawEvent{
		Type: "unknown\n" + canary, JSON: []byte(canary),
	}, errors.New(canary))
	if output.String() !=
		"kindle-lichess-bridge: normalize_reject event=unknown code=internal\n" {
		t.Fatalf("diagnostic output = %q", output.String())
	}
	if strings.Contains(output.String(), canary) {
		t.Fatalf("diagnostic output leaked untrusted data: %q", output.String())
	}
}
