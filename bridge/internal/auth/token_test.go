// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package auth

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadTokenRequiresRegular0600File(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	path := filepath.Join(directory, "token")
	if _, err := LoadToken(path); !errors.Is(err, ErrTokenMissing) {
		t.Fatalf("missing error = %v", err)
	}
	if err := os.WriteFile(path, []byte("test-secret\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadToken(path); !errors.Is(err, ErrTokenPermissions) {
		t.Fatalf("permissions error = %v", err)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		t.Fatal(err)
	}
	token, err := LoadToken(path)
	if err != nil || token.Bearer() != "test-secret" {
		t.Fatalf("token = %v, %v", token, err)
	}
}

func TestLoadTokenRejectsSymlinkEmptyMultilineAndOversized(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	target := filepath.Join(directory, "target")
	if err := os.WriteFile(target, []byte("secret"), 0o600); err != nil {
		t.Fatal(err)
	}
	symlink := filepath.Join(directory, "link")
	if err := os.Symlink(target, symlink); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadToken(symlink); !errors.Is(err, ErrTokenPermissions) {
		t.Fatalf("symlink error = %v", err)
	}

	for name, content := range map[string]string{
		"empty": " \n", "multiline": "one\ntwo", "oversized": strings.Repeat("x", maxTokenBytes+1),
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(directory, name)
			if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := LoadToken(path); !errors.Is(err, ErrTokenInvalid) {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

func TestTokenFormattingNeverLeaksValue(t *testing.T) {
	t.Parallel()
	canary := "runtime-secret-canary"
	token := Token{value: canary}
	formatted := fmt.Sprintf("%s %v %+v %#v %q", token, token, token, token, token)
	if strings.Contains(formatted, canary) {
		t.Fatalf("token leaked through formatting: %s", formatted)
	}
}
