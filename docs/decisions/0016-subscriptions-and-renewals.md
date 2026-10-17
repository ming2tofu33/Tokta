# ADR-0016: Track subscription cost manually, and fetch renewal dates where possible

- Status: Accepted
- Date: 2026-10-13

## Context

With many accounts, it is hard to know what AI subscriptions cost each month and when they renew. Plan prices change often and vary by region and tax.

## Decision

- For each account, the user enters an amount, a currency, a cycle (monthly or yearly) and one billing date. Tokta computes the next renewal, clamping to the last day of short months.
- Tokta does not prefill plan prices.
- Monthly totals add yearly plans divided by 12. Different currencies are shown side by side, with no exchange rates.
- Renewal dates are fetched automatically where available:
  - **Claude:** the organization's `subscription_details`. Only organization owners can read it, so member accounts reuse a date found by another account in the same organization.
  - **Cursor:** `billingCycleEnd`.
  - **Codex and Grok:** not available, so the user enters the date. Tokta does not decode tokens to find it.
- A manually entered date wins over a fetched one.
- Renewal alerts go out once per organization, not once per member account.

## Consequences

- Team plans should have the amount entered on one account only, or the monthly total double counts. The settings screen says so.
