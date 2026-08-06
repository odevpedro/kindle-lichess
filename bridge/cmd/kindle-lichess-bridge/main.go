// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/odevpedro/kindle-lichess/bridge/internal/app"
	"github.com/odevpedro/kindle-lichess/bridge/internal/auth"
	"github.com/odevpedro/kindle-lichess/bridge/internal/ipc"
	"github.com/odevpedro/kindle-lichess/bridge/internal/lichess"
	"github.com/odevpedro/kindle-lichess/bridge/internal/reconnect"
)

const defaultSocketPath = "/tmp/kindle-lichess.sock"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	os.Exit(run(ctx, os.Args[1:], os.Stderr))
}

func run(ctx context.Context, args []string, stderr io.Writer) int {
	flags := flag.NewFlagSet("kindle-lichess-bridge", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	socketPath := flags.String("socket", defaultSocketPath, "Unix socket path")
	tokenFile := flags.String("token-file", "", "0600 personal access token file")
	if err := flags.Parse(args); err != nil || flags.NArg() != 0 {
		writeError(stderr, "invalid_arguments")
		return 2
	}
	if *tokenFile == "" {
		writeError(stderr, "token_missing")
		return 2
	}

	token, err := auth.LoadToken(*tokenFile)
	if err != nil {
		writeError(stderr, safeErrorCode(err))
		return 1
	}
	transport := newTransport()
	defer transport.CloseIdleConnections()
	client, err := lichess.NewClient("https://lichess.org", &http.Client{Transport: transport}, token)
	if err != nil {
		writeError(stderr, "internal")
		return 1
	}
	server, err := ipc.Listen(*socketPath)
	if err != nil {
		writeError(stderr, safeErrorCode(err))
		return 1
	}
	err = server.Serve(ctx, func(sessionContext context.Context, connection net.Conn) error {
		return app.NewSession(client, reconnect.DefaultPolicy()).Run(sessionContext, connection)
	})
	if err == nil || errors.Is(err, context.Canceled) {
		return 0
	}
	writeError(stderr, safeErrorCode(err))
	return 1
}

func newTransport() *http.Transport {
	return &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          4,
		MaxIdleConnsPerHost:   2,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   15 * time.Second,
		ExpectContinueTimeout: time.Second,
		ResponseHeaderTimeout: 20 * time.Second,
	}
}

func safeErrorCode(err error) string {
	switch {
	case errors.Is(err, auth.ErrTokenMissing):
		return "token_missing"
	case errors.Is(err, auth.ErrTokenPermissions):
		return "token_permissions"
	case errors.Is(err, auth.ErrTokenInvalid):
		return "token_invalid"
	case errors.Is(err, ipc.ErrSocketInUse):
		return "socket_in_use"
	case errors.Is(err, ipc.ErrUnsafeSocketPath):
		return "unsafe_socket_path"
	default:
		return "internal"
	}
}

func writeError(destination io.Writer, code string) {
	_, _ = fmt.Fprintf(destination, "kindle-lichess-bridge: %s\n", code)
}
