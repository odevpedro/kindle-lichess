// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package stream

import (
	"bytes"
	"errors"
	"io"
	"strings"
	"testing"
)

type chunkReader struct {
	chunks [][]byte
}

type oneByteWriter struct {
	output bytes.Buffer
}

func (w *oneByteWriter) Write(value []byte) (int, error) {
	return w.output.Write(value[:1])
}

func (r *chunkReader) Read(destination []byte) (int, error) {
	if len(r.chunks) == 0 {
		return 0, io.EOF
	}
	chunk := r.chunks[0]
	r.chunks = r.chunks[1:]
	n := copy(destination, chunk)
	if n < len(chunk) {
		r.chunks = append([][]byte{chunk[n:]}, r.chunks...)
	}
	return n, nil
}

func TestReaderHandlesFragmentedAndGroupedLines(t *testing.T) {
	t.Parallel()
	reader := NewReader(&chunkReader{chunks: [][]byte{
		[]byte(`{"type":"game`),
		[]byte("State" + `"}` + "\n\n" + `{"type":"ping"}` + "\r\n"),
	}}, 128)

	first, err := reader.Next()
	if err != nil || string(first) != `{"type":"gameState"}` {
		t.Fatalf("first line = %q, %v", first, err)
	}
	second, err := reader.Next()
	if err != nil || string(second) != `{"type":"ping"}` {
		t.Fatalf("second line = %q, %v", second, err)
	}
	if _, err := reader.Next(); !errors.Is(err, io.EOF) {
		t.Fatalf("final error = %v, want EOF", err)
	}
}

func TestReaderHandlesEveryByteBoundary(t *testing.T) {
	t.Parallel()
	input := []byte(`{"v":1,"type":"connected"}` + "\n")
	chunks := make([][]byte, 0, len(input))
	for _, value := range input {
		chunks = append(chunks, []byte{value})
	}
	line, err := NewReader(&chunkReader{chunks: chunks}, 128).Next()
	if err != nil || !bytes.Equal(line, input[:len(input)-1]) {
		t.Fatalf("line = %q, %v", line, err)
	}
}

func TestReaderRejectsUnexpectedEOF(t *testing.T) {
	t.Parallel()
	_, err := NewReader(strings.NewReader(`{"partial":true}`), 128).Next()
	if !errors.Is(err, ErrTruncatedLine) {
		t.Fatalf("error = %v, want %v", err, ErrTruncatedLine)
	}
}

func TestReaderRejectsAndDrainsOversizedLine(t *testing.T) {
	t.Parallel()
	reader := NewReader(strings.NewReader(strings.Repeat("x", 40)+"\n{}\n"), 16)
	if _, err := reader.Next(); !errors.Is(err, ErrMessageTooLarge) {
		t.Fatalf("error = %v, want %v", err, ErrMessageTooLarge)
	}
	line, err := reader.Next()
	if err != nil || string(line) != "{}" {
		t.Fatalf("line after oversized input = %q, %v", line, err)
	}
}

func TestWriterEmitsExactlyOneBoundedLine(t *testing.T) {
	t.Parallel()
	var output bytes.Buffer
	writer := NewWriter(&output, 64)
	if err := writer.Write(map[string]any{"v": 1, "type": "pong"}); err != nil {
		t.Fatal(err)
	}
	if got := output.String(); got != "{\"type\":\"pong\",\"v\":1}\n" {
		t.Fatalf("output = %q", got)
	}
	if err := NewWriter(io.Discard, 4).Write(map[string]string{"long": "value"}); !errors.Is(err, ErrMessageTooLarge) {
		t.Fatalf("oversized write error = %v", err)
	}
}

func TestWriterCompletesPartialWrites(t *testing.T) {
	t.Parallel()
	destination := &oneByteWriter{}
	if err := NewWriter(destination, 64).Write(map[string]any{"v": 1}); err != nil {
		t.Fatal(err)
	}
	if got := destination.output.String(); got != "{\"v\":1}\n" {
		t.Fatalf("output = %q", got)
	}
}
