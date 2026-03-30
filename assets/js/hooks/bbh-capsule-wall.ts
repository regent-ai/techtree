import type { Hook, HookContext } from "phoenix_live_view"

import { animate } from "../../vendor/anime.esm.js"

type CapsuleState = {
  capsuleId: string
  lane: string
  lastEventKind: string
  lastEventAt: number
  activeAgents: number
  bestScore: number
  bestValidatedScore: number
  routeMaturity: string
}

type BbhCapsuleWallHook = HookContext &
  Hook & {
    previousCapsules?: Map<string, CapsuleState>
  }

function readNumber(value: string | undefined): number {
  if (!value) return 0
  const parsed = Number.parseFloat(value)
  return Number.isFinite(parsed) ? parsed : 0
}

function capsuleState(target: HTMLElement): CapsuleState {
  return {
    capsuleId: target.dataset.capsuleId || "",
    lane: target.dataset.lane || "",
    lastEventKind: target.dataset.lastEventKind || "",
    lastEventAt: readNumber(target.dataset.lastEventAt),
    activeAgents: readNumber(target.dataset.activeAgents),
    bestScore: readNumber(target.dataset.bestScore),
    bestValidatedScore: readNumber(target.dataset.bestValidatedScore),
    routeMaturity: target.dataset.routeMaturity || "",
  }
}

function ringTarget(target: HTMLElement): HTMLElement | null {
  return target.querySelector<HTMLElement>("[data-bbh-motion-layer='ring']")
}

function flashTarget(target: HTMLElement): HTMLElement | null {
  return target.querySelector<HTMLElement>("[data-bbh-motion-layer='flash']")
}

function pulseTile(
  target: HTMLElement,
  options: { scale?: [number, number, number]; boxShadow?: string[] } = {},
) {
  animate(target, {
    scale: options.scale || [1, 1.02, 1],
    boxShadow:
      options.boxShadow || [
        "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
        "0 0 0.85rem rgba(255,255,255,0.4), 0 1.5rem 3rem rgba(77, 53, 15, 0.18)",
        "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
      ],
    duration: 520,
    ease: "outCubic",
  })
}

function animateRing(target: HTMLElement, color: string, duration = 620) {
  const ring = ringTarget(target)
  if (!ring) return

  ring.style.borderColor = color

  animate(ring, {
    opacity: [0, 1, 0],
    scale: [0.82, 1.18],
    duration,
    ease: "outCubic",
  })
}

function animateFlash(target: HTMLElement, background: string, duration = 420) {
  const flash = flashTarget(target)
  if (!flash) return

  flash.style.background = background

  animate(flash, {
    opacity: [0, 0.9, 0],
    scale: [0.9, 1.08, 1.14],
    duration,
    ease: "outQuad",
  })
}

function animateEvent(target: HTMLElement, next: CapsuleState, previous: CapsuleState | undefined) {
  const activeCountIncreased = !!previous && next.activeAgents > previous.activeAgents
  const becameCold = !!previous && previous.activeAgents > 0 && next.activeAgents === 0
  const validatedImproved = !!previous && next.bestValidatedScore > previous.bestValidatedScore
  const bestImproved = !!previous && next.bestScore > previous.bestScore

  if (activeCountIncreased) {
    animateFlash(target, "radial-gradient(circle, rgba(255,255,255,0.9), transparent 72%)")
    pulseTile(target, {
      scale: [1, 1.025, 1],
      boxShadow: [
        "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
        "0 0 1.1rem rgba(255,255,255,0.7), 0 1.5rem 3rem rgba(77, 53, 15, 0.18)",
        "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
      ],
    })
  }

  if (becameCold) {
    animate(target, {
      opacity: [1, 0.72, 1],
      duration: 680,
      ease: "outQuad",
    })
  }

  switch (next.lastEventKind) {
    case "run_submitted":
      animateFlash(target, "linear-gradient(135deg, rgba(140, 92, 255, 0.6), transparent 68%)", 520)
      pulseTile(target)
      break
    case "personal_best":
      animateFlash(target, "radial-gradient(circle, rgba(84, 197, 108, 0.68), transparent 70%)")
      pulseTile(target, {
        boxShadow: [
          "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
          "0 0 1rem rgba(84,197,108,0.45), 0 1.5rem 3rem rgba(77, 53, 15, 0.18)",
          "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
        ],
      })
      break
    case "capsule_best":
      animateRing(target, "rgba(240, 185, 76, 0.96)")
      animateFlash(target, "radial-gradient(circle, rgba(240, 185, 76, 0.52), transparent 68%)")
      break
    case "validated_official_best":
      animateRing(target, "rgba(240, 185, 76, 1)", 760)
      animateFlash(target, "radial-gradient(circle, rgba(255, 243, 201, 0.9), transparent 66%)", 520)
      pulseTile(target, {
        scale: [1, 1.035, 1],
        boxShadow: [
          "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
          "0 0 1.15rem rgba(240,185,76,0.55), 0 1.7rem 3.1rem rgba(77, 53, 15, 0.18)",
          "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
        ],
      })
      break
    case "validation_confirmed":
      animateRing(target, "rgba(240, 185, 76, 0.84)")
      break
    case "validation_rejected":
    case "run_failed":
      animateFlash(target, "radial-gradient(circle, rgba(214, 73, 73, 0.68), transparent 70%)")
      pulseTile(target, {
        boxShadow: [
          "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
          "0 0 0.95rem rgba(214,73,73,0.48), 0 1.5rem 3rem rgba(77, 53, 15, 0.18)",
          "0 1.25rem 2.8rem rgba(77, 53, 15, 0.12)",
        ],
      })
      break
  }

  if (next.routeMaturity === "new" && (!previous || previous.routeMaturity !== next.routeMaturity)) {
    animateRing(target, "rgba(247, 157, 63, 0.9)", 560)
  }

  if (next.routeMaturity === "crowded" && (!previous || previous.routeMaturity !== next.routeMaturity)) {
    animateRing(target, "rgba(111, 92, 255, 0.78)", 620)
  }

  if (validatedImproved && next.lastEventKind !== "validated_official_best") {
    animateRing(target, "rgba(240, 185, 76, 0.92)")
  } else if (bestImproved && next.lastEventKind !== "capsule_best") {
    animateFlash(target, "radial-gradient(circle, rgba(84, 197, 108, 0.52), transparent 70%)")
  }
}

function readCapsules(root: HTMLElement): Map<string, CapsuleState> {
  const capsules = new Map<string, CapsuleState>()

  root.querySelectorAll<HTMLElement>("[data-capsule-id]").forEach((target) => {
    const state = capsuleState(target)
    if (state.capsuleId) {
      capsules.set(state.capsuleId, state)
    }
  })

  return capsules
}

export const BbhCapsuleWall = {
  mounted(this: BbhCapsuleWallHook) {
    this.previousCapsules = readCapsules(this.el as HTMLElement)
  },

  updated(this: BbhCapsuleWallHook) {
    const root = this.el as HTMLElement
    const nextCapsules = readCapsules(root)

    nextCapsules.forEach((next, capsuleId) => {
      const previous = this.previousCapsules?.get(capsuleId)
      const target = root.querySelector<HTMLElement>(`#bbh-capsule-${CSS.escape(capsuleId)}`)

      if (!target) return

      if (
        !previous ||
          previous.lastEventAt !== next.lastEventAt ||
          previous.lastEventKind !== next.lastEventKind ||
          previous.activeAgents !== next.activeAgents ||
          previous.bestScore !== next.bestScore ||
          previous.bestValidatedScore !== next.bestValidatedScore ||
          previous.routeMaturity !== next.routeMaturity ||
          previous.lane !== next.lane
      ) {
        animateEvent(target, next, previous)
      }
    })

    this.previousCapsules = nextCapsules
  },
} as Hook
