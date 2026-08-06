// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pedro Schmidt

package reconnect

import (
	"context"
	"time"
)

type Policy struct {
	Base  time.Duration
	Max   time.Duration
	Sleep func(context.Context, time.Duration) error
}

func DefaultPolicy() Policy {
	return Policy{Base: time.Second, Max: 30 * time.Second, Sleep: sleepContext}
}

func (p Policy) Delay(attempt int, serverHint time.Duration) time.Duration {
	if serverHint > 0 {
		return serverHint
	}
	base := p.Base
	if base <= 0 {
		base = time.Second
	}
	maximum := p.Max
	if maximum < base {
		maximum = 30 * time.Second
	}
	delay := base
	for index := 0; index < attempt && delay < maximum; index++ {
		if delay > maximum/2 {
			delay = maximum
			break
		}
		delay *= 2
	}
	if delay > maximum {
		return maximum
	}
	return delay
}

type Decision func(error) (retry bool, serverHint time.Duration)
type Notify func(attempt int, delay time.Duration, cause error)

func Run(ctx context.Context, policy Policy, operation func(context.Context) error,
	decision Decision, notify Notify) error {
	if policy.Sleep == nil {
		policy.Sleep = sleepContext
	}
	for attempt := 0; ; attempt++ {
		err := operation(ctx)
		if err == nil {
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		retry, hint := decision(err)
		if !retry {
			return err
		}
		delay := policy.Delay(attempt, hint)
		if notify != nil {
			notify(attempt+1, delay, err)
		}
		if err := policy.Sleep(ctx, delay); err != nil {
			return err
		}
	}
}

func sleepContext(ctx context.Context, duration time.Duration) error {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
