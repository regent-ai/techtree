This repository uses the root workflow as the canonical agent orchestration layer.

`AGENTS.md` is intentionally short. Treat it as the map, not the encyclopedia.

## Start Here

1. Read [WORKFLOW.md](WORKFLOW.md) for the active workflow contract.
2. Read [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md) for repo routing.
3. Read the domain policy docs that match your task:
   - [docs/regent-cli/README.md](docs/regent-cli/README.md) when the task also touches the standalone Regent CLI repo
   - [docs/AGENTS_BBH_UI.md](docs/AGENTS_BBH_UI.md) for BBH surface work
   - [docs/AUTH_BOUNDARY_AUDIT.md](docs/AUTH_BOUNDARY_AUDIT.md) for auth and trust-boundary work
   - [docs/SECURITY.md](docs/SECURITY.md)
   - [docs/VALIDATION.md](docs/VALIDATION.md)

## Core Rules

- Hard cutover only. Do not add backwards compatibility shims, migration glue, or dual paths unless explicitly requested.
- The root workflow is single-source-of-truth for agent execution. Do not revive the old `.claude` command flow.
- If work changes code in `/Users/sean/Documents/regent/techtree`, `/Users/sean/Documents/regent/regent-cli`, or `/Users/sean/Documents/regent/contracts/techtree`, it is not done until validation has been run in all three repos. Run `mix precommit` in `techtree`, `pnpm build`, `pnpm typecheck`, and `pnpm test` in `regent-cli`, and `forge test --offline` in `contracts/techtree`.
- Use `mix precommit` for Phoenix validation when touching app code.
- Use `Req` for Elixir HTTP calls. Do not introduce `:httpoison`, `:tesla`, or `:httpc`.
- Use Foundry for contract development and testing.
- Regent CLI live transport flows are daemon-owned. Do not add direct CLI-to-Phoenix socket paths.
- Prefer repository-local, versioned docs over off-repo context.
- Regent CLI terminal UI work should use the shared CLI palette unless a human explicitly asks for a different one:
  - `#315569` Charcoal Blue
  - `#034568` Yale Blue
  - `#FBF4DE` Ivory Mist
  - `#D4A756` Sunlit Clay
  - `#848078` Grey Olive

## Protected Work

The following work must never be auto-picked by autonomous agents unless a human explicitly assigns it:

- the shared contracts repo at `/Users/sean/Documents/regent/contracts/techtree`
- security-sensitive auth or trust-boundary changes
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows

See [docs/SECURITY.md](docs/SECURITY.md) for the full policy.
