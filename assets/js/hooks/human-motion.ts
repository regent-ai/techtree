import type { Hook, HookContext } from "phoenix_live_view"

import {
  prefersReducedMotion,
  revealSequence,
} from "../../../../design-system/regent_ui/assets/js/regent_motion"

function revealImmediately(targets: HTMLElement[]) {
  targets.forEach((target) => {
    target.style.opacity = "1"
    target.style.transform = "none"
    target.dataset.motionDone = "1"
  })
}

function markDone(targets: HTMLElement[]) {
  targets.forEach((target) => {
    target.dataset.motionDone = "1"
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
    this.reduceMotion = prefersReducedMotion()
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
    const revealSelector = "[data-motion='reveal']:not([data-motion-done='1'])"
    const graphSelector = "[data-motion='graph-node']:not([data-motion-done='1'])"
    const scoreSelector = "[data-motion='score-bar']:not([data-motion-done='1'])"

    const revealTargets = Array.from(
      this.el.querySelectorAll<HTMLElement>("[data-motion='reveal']:not([data-motion-done='1'])"),
    ) as HTMLElement[]

    const graphTargets = Array.from(
      this.el.querySelectorAll<HTMLElement>(
        "[data-motion='graph-node']:not([data-motion-done='1'])",
      ),
    ) as HTMLElement[]

    const scoreBarTargets = Array.from(
      this.el.querySelectorAll<HTMLElement>(
        "[data-motion='score-bar']:not([data-motion-done='1'])",
      ),
    ) as HTMLElement[]

    if (this.reduceMotion) {
      revealImmediately(revealTargets)
      revealImmediately(graphTargets)
      revealImmediately(scoreBarTargets)
      return
    }

    revealSequence(this.el, revealSelector, { translateY: 16, duration: 620, delay: 80 })
    markDone(revealTargets)
    revealSequence(this.el, scoreSelector, { translateY: 8, duration: 520, delay: 110 })
    markDone(scoreBarTargets)

    if (this.el.dataset.motionView === "graph") {
      revealSequence(this.el, graphSelector, { translateY: 12, duration: 520, delay: 55 })
      markDone(graphTargets)
    }
  },
} as Hook & { runMotion(this: HumanMotionHook): void }
