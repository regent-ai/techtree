import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"

interface PublicSiteElement extends HTMLElement {
  _publicCleanup?: () => void
  _publicReducedMotion?: boolean
}

const revealTargets = (root: HTMLElement) =>
  Array.from(
    root.querySelectorAll<HTMLElement>("[data-public-reveal]:not([data-public-motion-done='1'])"),
  )

const heroButtons = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>(".tt-public-hero-actions > *"))

const heroOrbs = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>(".tt-public-hero-video-orb"))

const setFeedback = (root: HTMLElement, selector: string | undefined, message: string) => {
  if (!selector) return
  const target = root.querySelector<HTMLElement>(selector)
  if (!target) return
  target.textContent = message
}

const copyValueFromButton = (button: HTMLElement) =>
  button.dataset.copyValue?.trim() || button.textContent?.trim() || ""

const runReveal = (root: PublicSiteElement) => {
  const targets = revealTargets(root)
  if (targets.length === 0) return

  if (root._publicReducedMotion) {
    targets.forEach((target) => {
      target.dataset.publicMotionDone = "1"
      target.style.transform = "none"
      target.style.opacity = "1"
    })

    return
  }

  targets.forEach((target) => {
    target.dataset.publicMotionDone = "1"
  })

  animate(targets, {
    opacity: [0, 1],
    translateY: [18, 0],
    delay: stagger(70),
    duration: 540,
    ease: "outExpo",
  })
}

const pulseButtons = (root: PublicSiteElement) => {
  if (root._publicReducedMotion) return

  const targets = heroButtons(root)
  if (targets.length === 0) return

  animate(targets, {
    translateY: [8, 0],
    opacity: [0, 1],
    delay: stagger(50, { start: 120 }),
    duration: 300,
    ease: "outExpo",
  })
}

const animateHeroMedia = (root: PublicSiteElement) => {
  if (root._publicReducedMotion) return

  const targets = heroOrbs(root)
  if (targets.length === 0) return

  animate(targets, {
    translateY: (_target: unknown, index: number) => (index % 2 === 0 ? [0, -14, 0] : [0, 14, 0]),
    translateX: (_target: unknown, index: number) => (index % 2 === 0 ? [0, 8, 0] : [0, -8, 0]),
    scale: [1, 1.04, 1],
    opacity: [0.6, 1, 0.6],
    delay: stagger(180),
    duration: 4200,
    ease: "inOutSine",
    loop: true,
  })
}

export const PublicSiteMotion: Hook = {
  mounted() {
    const root = this.el as PublicSiteElement
    const media = window.matchMedia("(prefers-reduced-motion: reduce)")
    root._publicReducedMotion = media.matches

    const onCopyClick = async (event: Event) => {
      const target = event.target as HTMLElement | null
      const button = target?.closest<HTMLElement>("[data-copy-button]")
      if (!button) return

      const value = copyValueFromButton(button)

      if (!value) {
        setFeedback(root, button.dataset.copyFeedback, "Nothing to copy yet.")
        return
      }

      try {
        await navigator.clipboard.writeText(value)
        setFeedback(root, button.dataset.copyFeedback, "Copied.")

        if (!root._publicReducedMotion) {
          animate(button, {
            scale: [1, 0.97, 1],
            duration: 240,
            ease: "outExpo",
          })
        }
      } catch {
        setFeedback(root, button.dataset.copyFeedback, "Copy failed. Select the text manually.")
      }
    }

    const onMotionChange = () => {
      root._publicReducedMotion = media.matches
      runReveal(root)
    }

    root.addEventListener("click", onCopyClick)
    media.addEventListener("change", onMotionChange)

    runReveal(root)
    pulseButtons(root)
    animateHeroMedia(root)

    root._publicCleanup = () => {
      root.removeEventListener("click", onCopyClick)
      media.removeEventListener("change", onMotionChange)
    }
  },

  updated() {
    const root = this.el as PublicSiteElement
    runReveal(root)
  },

  destroyed() {
    const root = this.el as PublicSiteElement
    root._publicCleanup?.()
  },
}
