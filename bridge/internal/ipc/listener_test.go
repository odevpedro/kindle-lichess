// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package ipc

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func socketPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "kindle-lichess.sock")
}

func TestListenCreates0600SocketAndRemovesIt(t *testing.T) {
	t.Parallel()
	path := socketPath(t)
	server, err := Listen(path)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Lstat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 || info.Mode()&os.ModeSocket == 0 {
		t.Fatalf("socket mode = %v", info.Mode())
	}
	if err := server.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains after close: %v", err)
	}
}

func TestListenRejectsRegularFileSymlinkAndActiveSocket(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	regular := filepath.Join(directory, "regular")
	if err := os.WriteFile(regular, []byte("do not delete"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Listen(regular); !errors.Is(err, ErrUnsafeSocketPath) {
		t.Fatalf("regular file error = %v", err)
	}
	content, _ := os.ReadFile(regular)
	if string(content) != "do not delete" {
		t.Fatal("regular file was modified")
	}

	symlink := filepath.Join(directory, "symlink")
	if err := os.Symlink(regular, symlink); err != nil {
		t.Fatal(err)
	}
	if _, err := Listen(symlink); !errors.Is(err, ErrUnsafeSocketPath) {
		t.Fatalf("symlink error = %v", err)
	}

	activePath := filepath.Join(directory, "active.sock")
	active, err := Listen(activePath)
	if err != nil {
		t.Fatal(err)
	}
	defer active.Close()
	if _, err := Listen(activePath); !errors.Is(err, ErrSocketInUse) {
		t.Fatalf("active socket error = %v", err)
	}
}

func TestListenReplacesOwnedStaleSocket(t *testing.T) {
	t.Parallel()
	path := socketPath(t)
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	listener.SetUnlinkOnClose(false)
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	server, err := Listen(path)
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
}

func TestServeAcceptsOneClientAndCancellationCleansUp(t *testing.T) {
	t.Parallel()
	path := socketPath(t)
	server, err := Listen(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	result := make(chan error, 1)
	go func() {
		result <- server.Serve(ctx, func(ctx context.Context, connection net.Conn) error {
			buffer := make([]byte, 4)
			_, err := io.ReadFull(connection, buffer)
			if err != nil {
				return err
			}
			if string(buffer) != "ping" {
				return errors.New("unexpected input")
			}
			_, err = connection.Write([]byte("pong"))
			if err != nil {
				return err
			}
			<-ctx.Done()
			return ctx.Err()
		})
	}()
	client, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	if _, err := client.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	response := make([]byte, 4)
	if _, err := io.ReadFull(client, response); err != nil || string(response) != "pong" {
		t.Fatalf("response = %q, %v", response, err)
	}
	if _, err := net.DialTimeout("unix", path, 50*time.Millisecond); err == nil {
		t.Fatal("second client connected")
	}
	cancel()
	if err := <-result; !errors.Is(err, context.Canceled) {
		t.Fatalf("serve error = %v", err)
	}
	if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("socket remains: %v", err)
	}
}

func TestCloseDoesNotRemoveReplacementPath(t *testing.T) {
	t.Parallel()
	path := socketPath(t)
	server, err := Listen(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("replacement"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := server.Close(); !errors.Is(err, ErrUnsafeSocketPath) {
		t.Fatalf("close error = %v", err)
	}
	content, err := os.ReadFile(path)
	if err != nil || string(content) != "replacement" {
		t.Fatalf("replacement changed: %q, %v", content, err)
	}
}
