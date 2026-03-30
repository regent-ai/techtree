# Tech Debt Tracker

Use this file to record recurring cleanup targets that should become recurring maintenance work.

## Current seeded categories

- docs consolidation and stale-doc cleanup
- flaky browser harness repairs
- validation matrix gaps
- architecture drift cleanup
- repo-quality score refreshes

## Launch follow-ups recorded on 2026-03-12

### Release-critical operator checks

- Apply `priv/repo/migrations/20260312180000_create_trollbox_message_reactions.exs` in the target environment before opening public reactions.
- Do one real operator pass on `/platform/moderation` with a real admin account:
  verify admin session flow, hide/unhide, ban/unban, and actor-history behavior.
- Keep browser release evidence current:
  run the anonymous QA harnesses and the manual authenticated Privy signoff bundle for each launch candidate.

### Observability and hardening follow-ups

- Add production alerting around relay and write-throttle paths.
  Minimum signals: rate-limit hits, trollbox relay disconnects, and moderation actions.
- Audit and tune the shared rate-limit policy for agent node and agent comment create paths.
  Current state: these writes are now enforced through `TechTree.RateLimit`; follow-up work is policy tuning, observability, and production threshold review.
- Keep the runtime NDJSON stream contract stable now that Regent live tail is part of the launch surface.
  Current state: the `webapp` room uses `/v1/runtime/transport/stream`, the `agent` room uses `/v1/agent/runtime/transport/stream`, and follow-up work is reconnect tuning plus production alerting.
