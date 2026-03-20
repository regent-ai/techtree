import type { Hook, HookContext } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"

function revealImmediately(targets: HTMLElement[]) {
  targets.forEach((target) => {
    target.style.opacity = "1"
    target.style.transform = "none"
    target.dataset.motionDone = "1"
  })
}

function revealAnimated(targets: HTMLElement[]) {
  if (targets.length === 0) {
    return
  }

  targets.forEach((target) => {
    target.dataset.motionDone = "1"
  })

  animate(targets, {
    opacity: [0, 1],
    translateY: [16, 0],
    duration: 620,
    delay: stagger(80, { start: 35 }),
    ease: "outQuad",
  })
}

function revealGraphNodes(targets: HTMLElement[]) {
  if (targets.length === 0) {
    return
  }

  targets.forEach((target) => {
    target.dataset.motionDone = "1"
  })

  animate(targets, {
    opacity: [0, 1],
    translateX: [-10, 0],
    scale: [0.985, 1],
    duration: 520,
    delay: stagger(55, { start: 20 }),
    ease: "outCubic",
  })
}

type HumanMotionHook = HookContext &
  Hook & {
    motionPreferenceMedia?: MediaQueryList
    reduceMotion?: boolean
    onMotionPreferenceChange?: (event: MediaQueryListEvent) => void
    runMotion: () => void
  }

export const HumanMotion = {
  mounted(this: HumanMotionHook) {
    this.motionPreferenceMedia = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.reduceMotion = this.motionPreferenceMedia.matches
    const onMotionPreferenceChange = (event: MediaQueryListEvent) => {
      this.reduceMotion = event.matches
      this.runMotion()
    }
    this.onMotionPreferenceChange = onMotionPreferenceChange

    this.motionPreferenceMedia.addEventListener("change", onMotionPreferenceChange)
    this.runMotion()
  },

  updated(this: HumanMotionHook) {
    this.runMotion()
  },

  destroyed(this: HumanMotionHook) {
    const handler = this.onMotionPreferenceChange

    if (this.motionPreferenceMedia && handler) {
      this.motionPreferenceMedia.removeEventListener("change", handler)
    }
  },

  runMotion(this: HumanMotionHook) {
    const revealTargets = Array.from(
      this.el.querySelectorAll<HTMLElement>("[data-motion='reveal']:not([data-motion-done='1'])"),
    ) as HTMLElement[]

    const graphTargets = Array.from(
      this.el.querySelectorAll<HTMLElement>(
        "[data-motion='graph-node']:not([data-motion-done='1'])",
      ),
    ) as HTMLElement[]

    if (this.reduceMotion) {
      revealImmediately(revealTargets)
      revealImmediately(graphTargets)
      return
    }

    revealAnimated(revealTargets)

    if (this.el.dataset.motionView === "graph") {
      revealGraphNodes(graphTargets)
    }
  },
} as Hook & { runMotion(this: HumanMotionHook): void }
