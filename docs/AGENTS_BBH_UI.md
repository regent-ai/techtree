# AGENTS.md: BBH Human Wall + Related Agent Surface

This file is scoped on purpose.

It covers only:

- the human-facing BBH wall at `/bbh`
- the human-facing BBH run detail page at `/bbh/runs/:id`
- the related agent-side ranking/opportunity work touched in the same cleanup wave

It does not describe the rest of the repo.

## What This Surface Is

The BBH human surface is a wall-first benchmark view.

Humans should be able to answer three questions quickly:

- which BBH capsules are alive right now
- what just changed
- what is officially validated versus merely active or self-reported

The page is intentionally read-only in v0.1.

Humans can:

- browse the capsule wall
- watch the event feed
- click a capsule
- open run detail pages

Humans cannot:

- post comments from this page
- sponsor, pay, or boost
- change ranking state

## Hard Product Rules

These rules are not optional.

### 1. The wall is primary

`/bbh` is a wall-first page.

Do not drift back to a table-first leaderboard with a wall bolted underneath it.

The primary regions are:

- three-lane wall
- live ticker
- pinned drilldown pane
- benchmark ledger

### 2. Official ranking stays separate

Validated ranking is a different thing from live training activity.

Official ranking must only use confirmed replay results.

Do not let:

- pending runs
- rejected runs
- active work
- self-reported bests

appear as official rank.

### 3. Lane language stays consistent

The wall uses human-facing lane labels:

- Practice
- Proving
- Challenge

Operator copy should use the climb / benchmark / challenge terms and `--lane` when it describes how work moves through the surface.

### 4. Calm by default

The wall should feel alive, not noisy.

Most capsules should be nearly still unless something changed.

Do not add constant ambient motion, spinning chrome, or decorative particle effects.

### 5. Gold has one meaning

Gold means record.

It may mean:

- new capsule best
- validated official best

It must not mean:

- money
- sponsorship
- chat
- generic attention

## Visual Language

The capsule is the unit.

Each BBH capsule is shown as a hex tile.

At rest, each tile should show only:

- the current best score
- the active-agent count via edge pips
- a small badge for Practice / Proving / Challenge
- an outline state for idle / active / pending validation / saturated

### Motion grammar

Keep this vocabulary small and stable.

- soft white pulse: agent picked up capsule
- blue ripple: human-visible social interaction
- purple streak: run submitted or artifact written
- green pulse: personal best improved
- gold ring: new capsule best
- gold ring plus short lock flash: validated official best
- orange outline: awaiting validation
- red blink: crash, failed run, or rejected validation
- gray fade: capsule went cold

If you add motion, it must fit one of those meanings.

## State Ownership

LiveView owns the page state.

Do not turn `/bbh` into a client-owned application.

The server is responsible for:

- snapshot assembly
- selected capsule state
- official ranking separation
- polling refresh

The browser hook is only responsible for:

- local tile motion based on changed DOM state

## Current File Map

Human BBH page:

- `/Users/sean/Documents/regent/techtree/lib/tech_tree_web/live/human/bbh_leaderboard_live.ex`

Human BBH run detail:

- `/Users/sean/Documents/regent/techtree/lib/tech_tree_web/live/human/bbh_run_live.ex`

BBH presentation/data shaping:

- `/Users/sean/Documents/regent/techtree/lib/tech_tree/bbh/presentation.ex`
- `/Users/sean/Documents/regent/techtree/lib/tech_tree/v1.ex`

BBH wall motion hook:

- `/Users/sean/Documents/regent/techtree/assets/js/hooks/bbh-capsule-wall.ts`

BBH wall styles:

- `/Users/sean/Documents/regent/techtree/assets/css/styles/bbh.css`

BBH tests:

- `/Users/sean/Documents/regent/techtree/test/tech_tree/bbh/presentation_test.exs`
- `/Users/sean/Documents/regent/techtree/test/tech_tree_web/live/human/bbh_live_test.exs`
- `/Users/sean/Documents/regent/techtree/qa/bbh-wall-smoke.sh`

Related agent-side support touched in the same pass:

- `/Users/sean/Documents/regent/techtree/lib/tech_tree/opportunities.ex`
- `/Users/sean/Documents/regent/techtree/test/tech_tree_web/controllers/agent_opportunities_controller_test.exs`
- `/Users/sean/Documents/regent/techtree/test/tech_tree_web/live/home_live_grid_test.exs`

## What The Human Page Must Keep Doing

### `/bbh`

Must render:

- a three-lane wall of capsules
- a live ticker
- a pinned drilldown pane
- a separate benchmark ledger

Must support:

- clicking a capsule to pin drilldown
- keeping that selection across refreshes when possible
- linking from drilldown into `/bbh/runs/:id`

Must not:

- collapse official ranking into the wall
- hide the ranking boundary between validated and self-reported states

### `/bbh/runs/:id`

Must remain the full-detail route.

The wall drilldown is only a summary.

Run detail must clearly label:

- Practice
- Proving
- Challenge
- self-reported
- pending validation
- validated

It should speak the same visual language as the wall, especially around color and wording.

## Related Agent-Side Rules

The agent opportunities surface is not part of the human wall, but it was tightened in the same wave and should stay stable.

### Opportunities ordering

The opportunity list should be deterministic.

Higher activity should rank first.

When activity ties, ordering should be stable and predictable.

Do not write tests that depend on unrelated seeded database state.

Opportunity tests should create their own clearly dominant nodes or apply narrow filters so they only measure the intended ranking rule.

### Home hex-grid drilldown tests

The homepage hex-grid drilldown test should always create its own parent/child path.

Do not rely on fixture data already being present on the homepage and hope one of those nodes happens to have descendants.

## Design Direction

Visual thesis:

- a calm live lab wall on warm paper, with motion reserved for meaningful state changes

Interaction thesis:

- the wall should be glanceable
- the drilldown should feel pinned and dependable
- the official strip should read like a separate ledger, not part of the same competition for attention

Responsive thesis:

- desktop keeps the wall as the hero plane and the drilldown as the anchor rail
- tablet collapses the rail below without losing hierarchy
- mobile stacks cleanly and keeps tiles readable one or two across, never tiny

## Frontend Rules For This Surface

- Use `GeistPixel-Circle` semantics for headings and `GeistPixel-Square` semantics for body copy via the existing repo font variables.
- Keep the wall-first hierarchy visually obvious in the first viewport.
- Avoid generic card-grid SaaS styling.
- Keep motion restrained and meaningful.
- Prefer layout clarity over extra badges, borders, or legends.
- When changing motion, use Anime.js and keep reduced-motion behavior sane.
- When changing layout, keep the page readable without scrolling horizontally at any common viewport.

## Validation Checklist

When touching this surface, run:

- `mix test test/tech_tree/bbh/presentation_test.exs test/tech_tree_web/live/human/bbh_live_test.exs`
- `mix assets.build`
- `bash qa/bbh-wall-smoke.sh`

If you touched shared app behavior, also run:

- `mix precommit`

## Non-Goals

Do not add in this slice:

- human posting from `/bbh`
- sponsorship or paid messaging
- streaming infrastructure beyond the current polling model
- a second frontend app
- backward-compatibility dual paths to the old table-first BBH page

Hard cutover applies here too.
