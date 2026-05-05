import type { Hook, HookContext } from "phoenix_live_view"

import { animate } from "animejs"

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
    reduceMotion?: MediaQueryList
    previousDrilldownId?: string
    cleanupMotionPreference?: () => void
  }

function shouldReduceMotion(hook: BbhCapsuleWallHook): boolean {
  return hook.reduceMotion?.matches ?? window.matchMedia("(prefers-reduced-motion: reduce)").matches
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

function clearCapsuleMotion(target: HTMLElement) {
  target.style.transform = ""
  target.style.opacity = ""

  target.querySelectorAll<HTMLElement>(".bbh-capsule-core, .bbh-capsule-ring, .bbh-capsule-flash").forEach((node) => {
    node.style.transform = ""
    node.style.opacity = ""
  })
}

function liveFlash(target: HTMLElement) {
  const flash = document.createElement("span")
  flash.className = "bbh-live-flash"
  flash.setAttribute("aria-hidden", "true")
  target.appendChild(flash)

  animate(flash, {
    opacity: [0, 1, 0],
    translateX: ["-24%", "24%"],
    duration: 260,
    ease: "outQuad",
  })

  window.setTimeout(() => {
    flash.remove()
  }, 280)
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
    duration: 260,
    ease: "outCubic",
  })
}

function animateRing(target: HTMLElement, color: string, duration = 280) {
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

function animateFlash(target: HTMLElement, background: string, duration = 240) {
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
      duration: 260,
      ease: "outQuad",
    })
  }

  switch (next.lastEventKind) {
    case "run_submitted":
      animateFlash(target, "linear-gradient(135deg, rgba(140, 92, 255, 0.6), transparent 68%)", 260)
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
      animateRing(target, "rgba(240, 185, 76, 1)", 300)
      animateFlash(target, "radial-gradient(circle, rgba(255, 243, 201, 0.9), transparent 66%)", 280)
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
    animateRing(target, "rgba(247, 157, 63, 0.9)", 260)
  }

  if (next.routeMaturity === "crowded" && (!previous || previous.routeMaturity !== next.routeMaturity)) {
    animateRing(target, "rgba(111, 92, 255, 0.78)", 280)
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
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.previousCapsules = readCapsules(this.el as HTMLElement)
    this.previousDrilldownId = (this.el as HTMLElement).querySelector<HTMLElement>(".bbh-drilldown[id]")?.id

    const syncReducedMotion = () => {
      if (!shouldReduceMotion(this)) return
      ;(this.el as HTMLElement)
        .querySelectorAll<HTMLElement>("[data-capsule-id]")
        .forEach(clearCapsuleMotion)
    }

    this.reduceMotion.addEventListener("change", syncReducedMotion)
    this.cleanupMotionPreference = () => {
      this.reduceMotion?.removeEventListener("change", syncReducedMotion)
    }
  },

  updated(this: BbhCapsuleWallHook) {
    const root = this.el as HTMLElement
    const nextCapsules = readCapsules(root)
    const reducedMotion = shouldReduceMotion(this)

    nextCapsules.forEach((next, capsuleId) => {
      const previous = this.previousCapsules?.get(capsuleId)
      const target = root.querySelector<HTMLElement>(`#bbh-capsule-${CSS.escape(capsuleId)}`)

      if (!target) return

      if (
        reducedMotion
      ) {
        clearCapsuleMotion(target)
        return
      }

      if (
        (!previous ||
          previous.lastEventAt !== next.lastEventAt ||
          previous.lastEventKind !== next.lastEventKind ||
          previous.activeAgents !== next.activeAgents ||
          previous.bestScore !== next.bestScore ||
          previous.bestValidatedScore !== next.bestValidatedScore ||
          previous.routeMaturity !== next.routeMaturity ||
          previous.lane !== next.lane)
      ) {
        animateEvent(target, next, previous)
      }
    })

    const drilldown = root.querySelector<HTMLElement>(".bbh-drilldown[id]")
    if (drilldown?.id && drilldown.id !== this.previousDrilldownId) {
      if (reducedMotion) {
        drilldown.style.transform = "none"
        drilldown.style.opacity = "1"
      } else {
        liveFlash(drilldown)
        animate(drilldown, {
          opacity: [0.82, 1],
          scale: [0.995, 1],
          duration: 240,
          ease: "outExpo",
        })
      }
    }

    this.previousDrilldownId = drilldown?.id
    this.previousCapsules = nextCapsules
  },

  destroyed(this: BbhCapsuleWallHook) {
    this.cleanupMotionPreference?.()
  },
} as Hook
