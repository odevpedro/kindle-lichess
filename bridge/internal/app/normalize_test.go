// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package app

import (
	"encoding/json"
	"testing"
)

func TestObjectIDRejectsMissingOrMalformedID(t *testing.T) {
	t.Parallel()
	for _, raw := range []string{"{}", "{\"id\":\"\"}", "{"} {
		if _, err := objectID(json.RawMessage(raw)); err == nil {
			t.Fatalf("accepted invalid object: %q", raw)
		}
	}
	id, err := objectID(json.RawMessage("{\"id\":\"challenge01\",\"future\":\"ignored\"}"))
	if err != nil || id != "challenge01" {
		t.Fatalf("id=%q err=%v", id, err)
	}
}

func TestNormalizeGameReferenceAcceptsLiveShapes(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name   string
		raw    string
		id     string
		status string
	}{
		{
			name: "gameStart status object",
			raw: `{"id":"gKLHWZev","gameId":"gKLHWZev","status":{"id":20,"name":"started"},
				"color":"white","variant":{"key":"standard"}}`,
			id: "gKLHWZev", status: "started",
		},
		{
			name: "gameStart string status",
			raw:  `{"id":"g1","status":"started"}`,
			id:   "g1", status: "started",
		},
		{
			name: "gameFinish via gameId and name-only id",
			raw:  `{"gameId":"g2","status":{"id":30,"name":"aborted"}}`,
			id:   "g2", status: "aborted",
		},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ref, err := normalizeGameReference(json.RawMessage(tc.raw))
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if ref["id"] != tc.id {
				t.Fatalf("id=%v want %q", ref["id"], tc.id)
			}
			if ref["status"] != tc.status {
				t.Fatalf("status=%v want %q", ref["status"], tc.status)
			}
		})
	}
	if _, err := objectID(json.RawMessage("{}")); err == nil {
		t.Fatal("empty object must still fail")
	}
	if _, err := normalizeGameReference(json.RawMessage("{\"color\":\"white\"}")); err == nil {
		t.Fatal("missing every id must still fail")
	}
}

func TestGameReferenceWinner(t *testing.T) {
	t.Parallel()
	ref, err := normalizeGameReference(json.RawMessage(`{"id":"g","winner":{"color":"black","id":"p"}}`))
	if err != nil || ref["winner"] != "black" {
		t.Fatalf("winner=%v err=%v", ref["winner"], err)
	}
	sref, err := normalizeGameReference(json.RawMessage(`{"id":"g","winner":"white"}`))
	if err != nil || sref["winner"] != "white" {
		t.Fatalf("winner=%v err=%v", sref["winner"], err)
	}
}
