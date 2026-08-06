// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package main

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRunRequiresTokenWithoutExposingPath(t *testing.T) {
	t.Parallel()
	canary := "secret-token-path-canary"
	var stderr bytes.Buffer
	exitCode := run(context.Background(), []string{
		"-token-file", filepath.Join(t.TempDir(), canary),
	}, &stderr)
	if exitCode != 1 || !strings.Contains(stderr.String(), "token_missing") {
		t.Fatalf("exit=%d stderr=%q", exitCode, stderr.String())
	}
	if strings.Contains(stderr.String(), canary) {
		t.Fatalf("stderr exposed token path: %q", stderr.String())
	}
}

func TestRunRejectsInvalidArgumentsWithoutEchoingThem(t *testing.T) {
	t.Parallel()
	canary := "secret-argument-canary"
	var stderr bytes.Buffer
	exitCode := run(context.Background(), []string{"-" + canary}, &stderr)
	if exitCode != 2 || stderr.String() != "kindle-lichess-bridge: invalid_arguments\n" {
		t.Fatalf("exit=%d stderr=%q", exitCode, stderr.String())
	}
}

func TestRunCancellationRemovesSocket(t *testing.T) {
	directory := t.TempDir()
	tokenPath := filepath.Join(directory, "token")
	if err := os.WriteFile(tokenPath, []byte("lifecycle-canary"), 0o600); err != nil {
		t.Fatal(err)
	}
	socketPath := filepath.Join(directory, "bridge.sock")
	ctx, cancel := context.WithCancel(context.Background())
	result := make(chan int, 1)
	var stderr bytes.Buffer
	go func() {
		result <- run(ctx, []string{"-socket", socketPath, "-token-file", tokenPath}, &stderr)
	}()
	waitForSocket(t, socketPath)
	cancel()
	select {
	case exitCode := <-result:
		if exitCode != 0 || stderr.Len() != 0 {
			t.Fatalf("exit=%d stderr=%q", exitCode, stderr.String())
		}
	case <-time.After(3 * time.Second):
		t.Fatal("bridge did not stop after cancellation")
	}
	if _, err := os.Lstat(socketPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains after cancellation: %v", err)
	}
}

func waitForSocket(t *testing.T, path string) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSocket != 0 {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("socket was not created")
}
