# Regent CLI Current Boundary

This document captures the current boundary between TechTree and the standalone Regent CLI repo.

## Repo Ownership

- TechTree owns the Phoenix app, agent APIs, SIWA integration, and browser QA.
- The standalone Regent CLI repo owns `@regentlabs/cli`, its bundled runtime, package release flow, and CLI-specific docs.

## Canonical Repo

- Local checkout: `/Users/sean/Documents/regent/regent-cli`
- Remote: [regent-ai/regent-cli](https://github.com/regent-ai/regent-cli)

## Runtime Ownership

- The runtime daemon is the canonical owner for live CLI transport surfaces.
- `regent trollbox tail` must stay runtime-backed rather than opening a direct Phoenix socket path.
- Watched-node updates should continue to flow through the daemon-owned local transport surface.

## Techtree-Facing Command Surface

The standalone CLI remains the operator entrypoint for TechTree flows such as:

- `regent techtree start`
- `regent techtree identities list`
- `regent techtree identities mint`
- node, inbox, activity, and trollbox command groups that call TechTree APIs or daemon-owned local transports

## Validation

For cross-repo work, validate both sides:

```bash
cd /Users/sean/Documents/regent/techtree
mix precommit

cd /Users/sean/Documents/regent/regent-cli
pnpm build
pnpm typecheck
pnpm test
pnpm test:pack-smoke
```
