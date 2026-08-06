// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package reconnect

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"
)

func TestPolicyBackoffAndServerHint(t *testing.T) {
	t.Parallel()
	policy := Policy{Base: time.Second, Max: 5 * time.Second}
	got := []time.Duration{
		policy.Delay(0, 0), policy.Delay(1, 0), policy.Delay(2, 0), policy.Delay(3, 0),
	}
	want := []time.Duration{time.Second, 2 * time.Second, 4 * time.Second, 5 * time.Second}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("delays = %v, want %v", got, want)
	}
	if delay := policy.Delay(20, 17*time.Second); delay != 17*time.Second {
		t.Fatalf("server hint = %v", delay)
	}
}

func TestRunRetriesThenSucceeds(t *testing.T) {
	t.Parallel()
	cause := errors.New("stream_eof")
	var calls int
	var sleeps []time.Duration
	policy := Policy{
		Base: time.Second,
		Max:  4 * time.Second,
		Sleep: func(_ context.Context, delay time.Duration) error {
			sleeps = append(sleeps, delay)
			return nil
		},
	}
	err := Run(context.Background(), policy, func(context.Context) error {
		calls++
		if calls < 3 {
			return cause
		}
		return nil
	}, func(error) (bool, time.Duration) { return true, 0 }, nil)
	if err != nil || calls != 3 || !reflect.DeepEqual(sleeps, []time.Duration{time.Second, 2 * time.Second}) {
		t.Fatalf("err=%v calls=%d sleeps=%v", err, calls, sleeps)
	}
}

func TestRunStopsOnContextCancellation(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(context.Background())
	policy := Policy{Sleep: func(ctx context.Context, _ time.Duration) error {
		cancel()
		<-ctx.Done()
		return ctx.Err()
	}}
	err := Run(ctx, policy, func(context.Context) error { return errors.New("again") },
		func(error) (bool, time.Duration) { return true, 0 }, nil)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("error = %v", err)
	}
}
