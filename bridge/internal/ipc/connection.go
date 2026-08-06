// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package ipc

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"

	"github.com/odevpedro/kindle-lichess/bridge/internal/protocol"
	"github.com/odevpedro/kindle-lichess/bridge/internal/stream"
)

type Connection struct {
	connection net.Conn
	reader     *stream.Reader
	writer     *stream.Writer
	writeMutex sync.Mutex
}

func NewConnection(connection net.Conn) *Connection {
	return &Connection{
		connection: connection,
		reader:     stream.NewReader(connection, stream.DefaultMaxMessageBytes),
		writer:     stream.NewWriter(connection, stream.DefaultMaxMessageBytes),
	}
}

func (c *Connection) Send(message any) error {
	c.writeMutex.Lock()
	defer c.writeMutex.Unlock()
	return c.writer.Write(message)
}

type CommandHandler func(context.Context, protocol.Command) error

func (c *Connection) ReadCommands(ctx context.Context, handler CommandHandler) error {
	for {
		line, err := c.reader.Next()
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
		command, err := protocol.DecodeCommand(line)
		if err != nil {
			code := "invalid_field"
			var validation *protocol.ValidationError
			if errors.As(err, &validation) {
				code = validation.Code
			}
			if sendErr := c.Send(map[string]any{
				"v": 1, "type": "error", "code": code,
				"message": "Invalid bridge message", "fatal": false,
			}); sendErr != nil {
				return sendErr
			}
			continue
		}
		if err := handler(ctx, command); err != nil {
			return err
		}
	}
}
