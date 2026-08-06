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
