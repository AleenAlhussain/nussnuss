import { Controller, Get, Header, Param, ParseUUIDPipe } from '@nestjs/common';
import { currency, expenseInGroupCurrency, formatNumber, owedInGroupCurrency } from '@nussnuss/core';
import { type AuthUser, CurrentUser } from '../common/http.js';
import { GroupsService } from '../groups/groups.service.js';
import { PlansService } from '../plans/plans.service.js';

/** RFC 4180 field: quoted when it holds a comma, quote or line break. A leading = + - @ is neutralised for spreadsheets. */
export function csvField(v: string | number): string {
  let s = String(v);
  if (typeof v === 'string' && /^[=+\-@\t\r]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = `'${s}`;
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

@Controller()
export class ExportController {
  constructor(
    private readonly groupsService: GroupsService,
    private readonly plans: PlansService,
  ) {}

  /** Every expense and payment as a spreadsheet, with each person's share in its own column (Plus). */
  @Get('groups/:id/export.csv')
  @Header('Content-Type', 'text/csv; charset=utf-8')
  async csv(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.plans.requirePlus(user.id, id);
    const g = await this.groupsService.detail(id, user.id);
    const num = (minor: number) => formatNumber(minor, g.currency).replace(/,/g, '');
    const head = ['Type', 'Date', 'Title', 'Category', 'Amount', 'Currency', 'Rate', `Amount (${g.currency})`, 'Paid by', ...g.members.map((m) => m.name)];
    const rows: (string | number)[][] = [head];
    const name = (mid: string) => g.members.find((m) => m.id === mid)?.name ?? '?';
    for (const e of [...g.expenses].reverse()) {
      const owed = owedInGroupCurrency(e, g.currency);
      rows.push([
        'Expense',
        e.spentAt.slice(0, 10),
        e.title,
        e.category,
        formatNumber(e.amount, e.currency).replace(/,/g, ''),
        e.currency,
        e.rate,
        num(expenseInGroupCurrency(e, g.currency)),
        name(e.paidBy),
        ...g.members.map((m) => (owed[m.id] ? num(owed[m.id]) : '')),
      ]);
    }
    for (const p of [...g.payments].reverse()) {
      rows.push(['Payment', p.paidAt.slice(0, 10), `${name(p.from)} paid ${name(p.to)}`, '', num(p.amount), g.currency, 1, num(p.amount), name(p.from), ...g.members.map(() => '')]);
    }
    rows.push([]);
    rows.push(['Balance', '', '', '', '', currency(g.currency).code, '', '', '', ...g.members.map((m) => num(g.balances[m.id] ?? 0))]);
    // The byte-order mark makes Excel read Arabic names correctly.
    return '﻿' + rows.map((r) => r.map(csvField).join(',')).join('\r\n') + '\r\n';
  }
}
