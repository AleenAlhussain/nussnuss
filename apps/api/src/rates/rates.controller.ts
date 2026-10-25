import { BadRequestException, Controller, Get, Query, ServiceUnavailableException } from '@nestjs/common';
import { CURRENCIES } from '@nussnuss/core';
import { z } from 'zod';
import { type AuthUser, CurrentUser, Zod } from '../common/http.js';
import { PlansService } from '../plans/plans.service.js';

const codes = new Set(CURRENCIES.map((c) => c.code));
const code = z.string().length(3).toUpperCase().refine((c) => codes.has(c), 'Unknown currency.');
const RateQuery = z.object({ from: code, to: code, groupId: z.uuid().optional() });

const cache = new Map<string, { at: number; rates: Record<string, number> }>();
const SIX_HOURS = 6 * 3600_000;

/** Latest rates for a base currency, kept for six hours. RATES_URL takes {base}; the default needs no key. */
async function ratesFor(base: string): Promise<{ at: number; rates: Record<string, number> }> {
  const hit = cache.get(base);
  if (hit && Date.now() - hit.at < SIX_HOURS) return hit;
  const url = (process.env.RATES_URL ?? 'https://open.er-api.com/v6/latest/{base}').replace('{base}', base);
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`rates ${res.status}`);
  const body = (await res.json()) as { rates?: Record<string, number>; conversion_rates?: Record<string, number> };
  const rates = body.rates ?? body.conversion_rates;
  if (!rates) throw new Error('no rates');
  const entry = { at: Date.now(), rates };
  cache.set(base, entry);
  return entry;
}

export function clearRatesCache() {
  cache.clear();
}

@Controller()
export class RatesController {
  constructor(private readonly plans: PlansService) {}

  /** How many `to` for one `from`, to prefill a foreign-currency expense (Plus). */
  @Get('rates')
  async rate(@CurrentUser() user: AuthUser, @Query(new Zod(RateQuery)) q: z.infer<typeof RateQuery>) {
    await this.plans.requirePlus(user.id, q.groupId);
    if (q.from === q.to) return { from: q.from, to: q.to, rate: 1, at: new Date().toISOString() };
    let entry;
    try {
      entry = await ratesFor(q.from);
    } catch {
      throw new ServiceUnavailableException('Exchange rates are not available right now. Type the rate instead.');
    }
    const rate = entry.rates[q.to];
    if (!rate) throw new BadRequestException(`No rate from ${q.from} to ${q.to}.`);
    return { from: q.from, to: q.to, rate, at: new Date(entry.at).toISOString() };
  }
}
