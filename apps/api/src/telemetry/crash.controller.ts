import { Body, Controller, HttpCode, Logger, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { z } from 'zod';
import { Public, Zod } from '../common/http.js';

/**
 * Crash reports from the apps. Off unless CRASH_REPORTS=log. Nothing personal is accepted: an error
 * message, a stack trace with file names, the app version and platform. Reports are written to the
 * server log as one JSON line each, where any log tool (or a Sentry/Crashlytics forwarder) can pick them up.
 */
const CrashBody = z.object({
  app: z.enum(['web', 'ios', 'android']),
  version: z.string().max(40),
  message: z.string().max(500),
  stack: z.string().max(8000).optional(),
});

const scrub = (s: string) =>
  s
    // Tokens, invite codes and anything that looks like a long secret.
    .replace(/\b[A-Za-z0-9_-]{32,}\b/g, '[redacted]')
    .replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, '[email]');

@Controller()
export class CrashController {
  private readonly log = new Logger('crash');

  @Public()
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('telemetry/crash')
  @HttpCode(204)
  report(@Body(new Zod(CrashBody)) body: z.infer<typeof CrashBody>) {
    if (process.env.CRASH_REPORTS !== 'log') return;
    this.log.error(JSON.stringify({ app: body.app, version: body.version, message: scrub(body.message), stack: body.stack ? scrub(body.stack) : undefined }));
  }
}

/**
 * How long the five main jobs take (phase 0 of the design plan): which job, how many milliseconds,
 * whether it finished, the app and version. No account, device or group is sent or stored. Off unless
 * TIMINGS=log; each timing is one JSON line in the server log, ready for any log tool to chart.
 */
const TimingBody = z.object({
  app: z.enum(['web', 'ios', 'android']),
  version: z.string().max(40),
  job: z.enum(['add_expense', 'uneven_split', 'settle', 'invite', 'find_balance']),
  ms: z.number().int().min(0).max(600_000),
  ok: z.boolean(),
});

@Controller()
export class TimingController {
  private readonly log = new Logger('timing');

  @Public()
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @Post('telemetry/timing')
  @HttpCode(204)
  report(@Body(new Zod(TimingBody)) body: z.infer<typeof TimingBody>) {
    if (process.env.TIMINGS !== 'log') return;
    this.log.log(JSON.stringify(body));
  }
}
