import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"

interface HomeStoryRailElement extends HTMLElement {
  _homeStoryObserver?: IntersectionObserver
  _homeStoryReduceMotion?: boolean
}

const storyTargets = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>("[data-story-reveal]"))

const revealTarget = (target: HTMLElement, immediate = false) => {
  if (target.dataset.storySeen === "true") return

  target.dataset.storySeen = "true"

  animate(target, {
    opacity: immediate ? [0.88, 1] : [0, 1],
    translateY: immediate ? [0, 0] : [14, 0],
    scale: immediate ? [1, 1] : [0.99, 1],
    duration: immediate ? 180 : 360,
    ease: "outExpo",
  })
}

const revealAll = (root: HTMLElement) => {
  const targets = storyTargets(root).filter((target) => target.dataset.storySeen !== "true")
  if (targets.length === 0) return

  for (const target of targets) target.dataset.storySeen = "true"

  animate(targets, {
    opacity: [0, 1],
    translateY: [14, 0],
    scale: [0.99, 1],
    delay: stagger(56),
    duration: 340,
    ease: "outExpo",
  })
}

export const HomeStoryRail: Hook = {
  mounted() {
    const root = this.el as HomeStoryRailElement
    const media = window.matchMedia("(prefers-reduced-motion: reduce)")

    root._homeStoryReduceMotion = media.matches

    if (root._homeStoryReduceMotion) {
      return
    }

    const targets = storyTargets(root)

    if (targets.length === 0) {
      return
    }

    root._homeStoryObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue
          revealTarget(entry.target as HTMLElement)
          root._homeStoryObserver?.unobserve(entry.target)
        }
      },
      {
        threshold: 0.24,
        rootMargin: "0px 0px -8% 0px",
      },
    )

    for (const target of targets) {
      root._homeStoryObserver.observe(target)
    }
  },

  updated() {
    const root = this.el as HomeStoryRailElement

    if (root._homeStoryReduceMotion) {
      return
    }

    const observer = root._homeStoryObserver

    if (!observer) {
      revealAll(root)
      return
    }

    for (const target of storyTargets(root)) {
      if (target.dataset.storySeen === "true") continue
      observer.observe(target)
    }
  },

  destroyed() {
    const root = this.el as HomeStoryRailElement
    root._homeStoryObserver?.disconnect()
  },
}
