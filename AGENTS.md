This repository uses Symphony as the canonical agent orchestration layer.

`AGENTS.md` is intentionally short. Treat it as the map, not the encyclopedia.

## Start Here

1. Read [WORKFLOW.md](WORKFLOW.md) for the active Symphony contract.
2. Read [docs/CODEBASE_MAP.md](docs/CODEBASE_MAP.md) for repo routing.
3. Read the domain policy docs that match your task:
   - [docs/regent-cli/README.md](docs/regent-cli/README.md) when touching `regent-cli/`
   - [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
   - [docs/FRONTEND.md](docs/FRONTEND.md)
   - [docs/RELIABILITY.md](docs/RELIABILITY.md)
   - [docs/SECURITY.md](docs/SECURITY.md)
   - [docs/VALIDATION.md](docs/VALIDATION.md)

## Core Rules

- Hard cutover only. Do not add backwards compatibility shims, migration glue, or dual paths unless explicitly requested.
- The root workflow is single-source-of-truth for agent execution. Do not revive the old `.claude` command flow.
- Use `mix precommit` for Phoenix validation when touching app code.
- Use `Req` for Elixir HTTP calls. Do not introduce `:httpoison`, `:tesla`, or `:httpc`.
- Use Foundry for contract development and testing.
- `regent-cli` live transport flows are daemon-owned. Do not add direct CLI-to-Phoenix socket paths.
- Techtree chain support is Ethereum mainnet plus Sepolia only. Do not reintroduce Base.
- Prefer repository-local, versioned docs over off-repo context.

## Protected Work

The following work must never be auto-picked by Symphony agents unless a human explicitly assigns it:

- `contracts/`
- security-sensitive auth or trust-boundary changes
- deploy and Fly.io changes
- database migrations and schema transitions
- billing, payment, or value-transfer flows

See [docs/SECURITY.md](docs/SECURITY.md) for the full policy.
