# Payment links and money circles: the partner interface

Today NussNuss never touches money. "Pay with" opens a payment service the receiver chose (an InstaPay or PayPal.me link, a Wise page) or copies an IBAN or wallet number, and the payer marks the transfer paid. Money circles only track turns and payments. This keeps NussNuss outside payment and savings regulation.

Earning from payments later needs a licensed partner (a bank, a wallet, or a regulated savings platform) that moves the money and pays a referral or revenue share. This is the interface the code is shaped for, so a partner can be added without changing the screens.

## What exists

- `PayTo` on each account (`kind`, `value`, `label`): `iban`, `instapay`, `stcpay`, `phone`, `paypal`, `wise`, `link`. Checked by the API (`apps/api/src/auth/auth.controller.ts`).
- `payAction(payTo, amount, currency)` in `packages/core/src/extras.ts` (and `apps/mobile/lib/core/extras.dart`): returns `{ open: url }` or `{ copy: text }`. This is the single place that decides what "Pay with" does.
- Payments are recorded with a client id (`POST /groups/:id/payments { id, from, to, amount }`), so a confirmation can be replayed safely.

## Adding a partner

1. **A new kind.** Add the partner as a `PayToKind` (for example `partnerwallet`) in the core type, the API schema and the i18n keys (`pay_partnerwallet`). The receiver links their partner account once (OAuth with the partner); store only the partner's account reference, never credentials.
2. **A payment intent.** `payAction` returns `{ open: url }` for the partner's hosted checkout, built by the API, never by the client:

   ```
   POST /payments/intents   { groupId, from, to, amount, currency, provider }
     → { intentId, url }     url = partner checkout with the amount and a return link
   ```

   The API signs the request to the partner with the partner's server key (env, like the store keys today) and keeps `intentId → (group, from, to, amount)`.
3. **Confirmation by webhook, not by the app.** The partner calls `POST /webhooks/<provider>` when the money arrives. The API checks the signature, then records the payment with `id = intentId` (idempotent), which bumps the group version and reaches every screen through the live stream. The payer never has to tap "Mark as paid".
4. **Money circles.** The same intents, with `circleId` and `round` instead of `to`; the webhook calls the existing `circles/:id/paid` logic. Holding the pot between rounds is the partner's licensed activity, never NussNuss's.
5. **Revenue.** The partner pays NussNuss per completed intent (a referral fee or a share of the partner's fee). NussNuss adds no fee of its own to splitting.

## Before switching it on

- A signed agreement and the partner's licence for each country (Egypt: InstaPay is run by the banks; Saudi Arabia: wallets are licensed by SAMA; UAE: by the Central Bank).
- Privacy policy and store privacy answers updated (the partner becomes a data recipient for payers who use it).
- Show clearly who is moving the money ("Paid through <partner>"), and keep the free "copy the IBAN" route available.
