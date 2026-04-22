import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"

interface LandingPageElement extends HTMLElement {
  _landingCleanup?: () => void
  _landingReducedMotion?: boolean
}

const revealTargets = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>("[data-landing-reveal]"))

const agentLinks = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>("[data-agent-link]"))

const copyButton = (root: HTMLElement) =>
  root.querySelector<HTMLButtonElement>("[data-copy-button]")

const feedbackNode = (root: HTMLElement) =>
  root.querySelector<HTMLElement>("#landing-copy-feedback")

const commandNode = (root: HTMLElement) =>
  root.querySelector<HTMLElement>("#landing-install-command")

const setFeedback = (root: HTMLElement, message: string) => {
  const target = feedbackNode(root)
  if (!target) return
  target.textContent = message
}

const runReveal = (root: LandingPageElement) => {
  if (root._landingReducedMotion) return

  const targets = revealTargets(root)
  if (targets.length === 0) return

  animate(targets, {
    translateY: [16, 0],
    delay: stagger(56),
    duration: 420,
    ease: "outExpo",
  })
}

const pulseCommand = (root: LandingPageElement) => {
  if (root._landingReducedMotion) return
  const target = commandNode(root)
  if (!target) return

  animate(target, {
    scale: [0.99, 1],
    duration: 240,
    ease: "outExpo",
  })
}

const nudgeAgents = (root: LandingPageElement) => {
  if (root._landingReducedMotion) return
  const targets = agentLinks(root)
  if (targets.length === 0) return

  animate(targets, {
    translateY: [8, 0],
    delay: stagger(40, { start: 140 }),
    duration: 260,
    ease: "outExpo",
  })
}

export const LandingPage: Hook = {
  mounted() {
    const root = this.el as LandingPageElement
    const media = window.matchMedia("(prefers-reduced-motion: reduce)")
    const button = copyButton(root)

    root._landingReducedMotion = media.matches

    runReveal(root)
    nudgeAgents(root)

    const onCopy = async () => {
      const value = button?.dataset.copyValue?.trim() || ""

      if (!value) {
        setFeedback(root, "Nothing to copy yet.")
        return
      }

      try {
        await navigator.clipboard.writeText(value)
        setFeedback(root, "Copied the install line.")
        pulseCommand(root)

        if (button && !root._landingReducedMotion) {
          animate(button, {
            scale: [1, 0.97, 1],
            duration: 220,
            ease: "outExpo",
          })
        }
      } catch {
        setFeedback(root, "Copy failed. Select the line manually.")
      }
    }

    const onMotionChange = () => {
      root._landingReducedMotion = media.matches
    }

    button?.addEventListener("click", onCopy)

    if ("addEventListener" in media) {
      media.addEventListener("change", onMotionChange)
    } else {
      const legacyMedia = media as MediaQueryList & {
        addListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
        removeListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
      }

      legacyMedia.addListener(onMotionChange)
    }

    root._landingCleanup = () => {
      button?.removeEventListener("click", onCopy)

      if ("removeEventListener" in media) {
        media.removeEventListener("change", onMotionChange)
      } else {
        const legacyMedia = media as MediaQueryList & {
          addListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
          removeListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
        }

        legacyMedia.removeListener(onMotionChange)
      }
    }
  },

  destroyed() {
    const root = this.el as LandingPageElement
    root._landingCleanup?.()
  },
}
