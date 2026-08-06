// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package auth

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
)

const maxTokenBytes = 4096

var (
	ErrTokenMissing     = errors.New("token_missing")
	ErrTokenPermissions = errors.New("token_permissions")
	ErrTokenInvalid     = errors.New("token_invalid")
)

// Token deliberately redacts every formatting path. Bearer is used only while constructing
// the Authorization header and must never be logged or sent over IPC.
type Token struct {
	value string
}

func (Token) String() string                   { return "<redacted>" }
func (Token) GoString() string                 { return "auth.Token{<redacted>}" }
func (t Token) Bearer() string                 { return t.value }
func (t Token) Empty() bool                    { return t.value == "" }
func (t Token) Format(state fmt.State, _ rune) { _, _ = io.WriteString(state, "<redacted>") }

func LoadToken(path string) (Token, error) {
	info, err := os.Lstat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return Token{}, ErrTokenMissing
		}
		return Token{}, fmt.Errorf("read token metadata: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm() != 0o600 {
		return Token{}, ErrTokenPermissions
	}

	file, err := os.Open(path)
	if err != nil {
		return Token{}, fmt.Errorf("open token: %w", err)
	}
	defer file.Close()

	content, err := io.ReadAll(io.LimitReader(file, maxTokenBytes+1))
	if err != nil {
		return Token{}, fmt.Errorf("read token: %w", err)
	}
	if len(content) > maxTokenBytes {
		return Token{}, ErrTokenInvalid
	}
	value := strings.TrimSpace(string(content))
	if value == "" || strings.ContainsAny(value, "\r\n\x00") {
		return Token{}, ErrTokenInvalid
	}
	return Token{value: value}, nil
}
