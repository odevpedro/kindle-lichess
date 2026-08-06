// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

// Package ipc owns the single-client Unix socket used by the Lua plugin.
package ipc

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

var (
	ErrSocketInUse      = errors.New("socket_in_use")
	ErrUnsafeSocketPath = errors.New("unsafe_socket_path")
)

type socketIdentity struct {
	device uint64
	inode  uint64
}

type Server struct {
	path      string
	identity  socketIdentity
	listener  *net.UnixListener
	mutex     sync.Mutex
	client    *net.UnixConn
	closed    bool
	closeDone chan struct{}
	closeErr  error
}

func Listen(path string) (*Server, error) {
	if !filepath.IsAbs(path) || filepath.Clean(path) == "/" {
		return nil, ErrUnsafeSocketPath
	}
	if err := prepareSocketPath(path); err != nil {
		return nil, err
	}
	address := &net.UnixAddr{Name: path, Net: "unix"}
	listener, err := net.ListenUnix("unix", address)
	if err != nil {
		return nil, fmt.Errorf("listen unix socket: %w", err)
	}
	listener.SetUnlinkOnClose(false)
	if err := os.Chmod(path, 0o600); err != nil {
		_ = listener.Close()
		_ = os.Remove(path)
		return nil, fmt.Errorf("chmod unix socket: %w", err)
	}
	identity, err := identifySocket(path)
	if err != nil {
		_ = listener.Close()
		_ = os.Remove(path)
		return nil, err
	}
	return &Server{
		path: path, identity: identity, listener: listener, closeDone: make(chan struct{}),
	}, nil
}

func prepareSocketPath(path string) error {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspect socket path: %w", err)
	}
	if info.Mode()&os.ModeSocket == 0 || info.Mode()&os.ModeSymlink != 0 {
		return ErrUnsafeSocketPath
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != uint32(os.Geteuid()) {
		return ErrUnsafeSocketPath
	}
	connection, dialErr := net.DialTimeout("unix", path, 100*time.Millisecond)
	if dialErr == nil {
		_ = connection.Close()
		return ErrSocketInUse
	}
	if !errors.Is(dialErr, syscall.ECONNREFUSED) && !errors.Is(dialErr, os.ErrNotExist) {
		return ErrSocketInUse
	}
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("remove stale socket: %w", err)
	}
	return nil
}

func identifySocket(path string) (socketIdentity, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return socketIdentity{}, fmt.Errorf("stat unix socket: %w", err)
	}
	if info.Mode()&os.ModeSocket == 0 || info.Mode()&os.ModeSymlink != 0 {
		return socketIdentity{}, ErrUnsafeSocketPath
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return socketIdentity{}, ErrUnsafeSocketPath
	}
	return socketIdentity{device: uint64(stat.Dev), inode: stat.Ino}, nil
}

// Serve accepts exactly one client. Closing the context interrupts Accept and any active
// connection, then removes only the socket inode created by this Server.
func (s *Server) Serve(ctx context.Context, handler func(context.Context, net.Conn) error) (serveErr error) {
	defer func() {
		if closeErr := s.Close(); serveErr == nil && closeErr != nil {
			serveErr = closeErr
		}
	}()
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			_ = s.Close()
		case <-done:
		}
	}()
	defer close(done)

	connection, err := s.listener.AcceptUnix()
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return fmt.Errorf("accept unix client: %w", err)
	}
	s.mutex.Lock()
	if s.closed {
		s.mutex.Unlock()
		_ = connection.Close()
		return context.Canceled
	}
	s.client = connection
	_ = s.listener.Close()
	s.mutex.Unlock()

	err = handler(ctx, connection)
	_ = connection.Close()
	s.mutex.Lock()
	s.client = nil
	s.mutex.Unlock()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return err
}

func (s *Server) Close() error {
	s.mutex.Lock()
	if s.closed {
		done := s.closeDone
		s.mutex.Unlock()
		<-done
		s.mutex.Lock()
		defer s.mutex.Unlock()
		return s.closeErr
	}
	s.closed = true
	listener := s.listener
	client := s.client
	s.mutex.Unlock()

	if client != nil {
		_ = client.Close()
	}
	if listener != nil {
		_ = listener.Close()
	}
	closeErr := s.removeOwnSocket()
	s.mutex.Lock()
	s.closeErr = closeErr
	close(s.closeDone)
	s.mutex.Unlock()
	return closeErr
}

func (s *Server) removeOwnSocket() error {
	identity, err := identifySocket(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		var pathError *os.PathError
		if errors.As(err, &pathError) && errors.Is(pathError.Err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if identity != s.identity {
		return ErrUnsafeSocketPath
	}
	if err := os.Remove(s.path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("remove unix socket: %w", err)
	}
	return nil
}
