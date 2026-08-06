// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

// Package stream implements bounded JSON Lines framing. It intentionally does not assume
// that transport reads align with lines.
package stream

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
)

const DefaultMaxMessageBytes = 65_536

var (
	ErrMessageTooLarge = errors.New("message_too_large")
	ErrTruncatedLine   = errors.New("truncated_json_line")
)

type Reader struct {
	reader *bufio.Reader
	max    int
}

func NewReader(source io.Reader, maxMessageBytes int) *Reader {
	if maxMessageBytes <= 0 {
		maxMessageBytes = DefaultMaxMessageBytes
	}
	return &Reader{
		reader: bufio.NewReaderSize(source, maxMessageBytes+1),
		max:    maxMessageBytes,
	}
}

// Next returns the next non-empty line without its newline. Empty and CRLF-only lines are
// keep-alives and are skipped. The configured limit includes the newline when present.
func (r *Reader) Next() ([]byte, error) {
	for {
		line, err := r.reader.ReadSlice('\n')
		if errors.Is(err, bufio.ErrBufferFull) {
			r.drainOversizedLine()
			return nil, ErrMessageTooLarge
		}
		if len(line) > r.max {
			return nil, ErrMessageTooLarge
		}
		if errors.Is(err, io.EOF) {
			if len(line) == 0 {
				return nil, io.EOF
			}
			return nil, ErrTruncatedLine
		}
		if err != nil {
			return nil, err
		}

		line = bytes.TrimSuffix(line, []byte{'\n'})
		line = bytes.TrimSuffix(line, []byte{'\r'})
		if len(line) == 0 {
			continue
		}
		return bytes.Clone(line), nil
	}
}

func (r *Reader) drainOversizedLine() {
	for {
		_, err := r.reader.ReadSlice('\n')
		if err == nil || errors.Is(err, io.EOF) {
			return
		}
		if !errors.Is(err, bufio.ErrBufferFull) {
			return
		}
	}
}

type Writer struct {
	writer io.Writer
	max    int
}

func NewWriter(destination io.Writer, maxMessageBytes int) *Writer {
	if maxMessageBytes <= 0 {
		maxMessageBytes = DefaultMaxMessageBytes
	}
	return &Writer{writer: destination, max: maxMessageBytes}
}

func (w *Writer) Write(message any) error {
	encoded, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("encode json line: %w", err)
	}
	if len(encoded)+1 > w.max {
		return ErrMessageTooLarge
	}
	encoded = append(encoded, '\n')
	for len(encoded) > 0 {
		written, err := w.writer.Write(encoded)
		if err != nil {
			return fmt.Errorf("write json line: %w", err)
		}
		if written == 0 {
			return fmt.Errorf("write json line: %w", io.ErrShortWrite)
		}
		encoded = encoded[written:]
	}
	return nil
}
