// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package ipc

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"testing"

	"github.com/odevpedro/kindle-lichess/bridge/internal/protocol"
	"github.com/odevpedro/kindle-lichess/bridge/internal/stream"
)

func TestConnectionRecoversFromInvalidJSONAndContinues(t *testing.T) {
	t.Parallel()
	serverSide, clientSide := net.Pipe()
	defer serverSide.Close()
	defer clientSide.Close()
	connection := NewConnection(serverSide)
	result := make(chan error, 1)
	go func() {
		result <- connection.ReadCommands(context.Background(), func(_ context.Context, command protocol.Command) error {
			return connection.Send(map[string]any{
				"v": 1, "type": "pong", "nonce": command.Nonce,
			})
		})
	}()

	if _, err := io.WriteString(clientSide, "not-json\n"+`{"v":1,"type":"ping","nonce":"n1"}`+"\n"); err != nil {
		t.Fatal(err)
	}
	reader := stream.NewReader(clientSide, stream.DefaultMaxMessageBytes)
	first, err := reader.Next()
	if err != nil {
		t.Fatal(err)
	}
	var firstMessage map[string]any
	if err := json.Unmarshal(first, &firstMessage); err != nil || firstMessage["type"] != "error" || firstMessage["fatal"] != false {
		t.Fatalf("first response = %s, %v", first, err)
	}
	second, err := reader.Next()
	if err != nil {
		t.Fatal(err)
	}
	var secondMessage map[string]any
	if err := json.Unmarshal(second, &secondMessage); err != nil || secondMessage["type"] != "pong" || secondMessage["nonce"] != "n1" {
		t.Fatalf("second response = %s, %v", second, err)
	}
	_ = clientSide.Close()
	if err := <-result; err != nil {
		t.Fatal(err)
	}
}
