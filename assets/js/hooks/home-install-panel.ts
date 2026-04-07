import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"

interface HomeInstallPanelElement extends HTMLElement {
  _homeInstallCleanup?: () => void
  _homeInstallCopyValue?: string
  _homeInstallReduceMotion?: boolean
}

const feedback = (root: HTMLElement) =>
  root.querySelector<HTMLElement>("[data-install-feedback]")

const command = (root: HTMLElement) =>
  root.querySelector<HTMLElement>("[data-install-command]")

const copyButton = (root: HTMLElement) =>
  root.querySelector<HTMLButtonElement>("[data-install-copy]")

const revealTargets = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>("[data-install-reveal]"))

const setFeedback = (root: HTMLElement, message: string) => {
  const target = feedback(root)
  if (!target) return
  target.textContent = message
}

const runReveal = (root: HomeInstallPanelElement, immediate = false) => {
  if (root._homeInstallReduceMotion) return

  const targets = revealTargets(root)
  if (targets.length === 0) return

  animate(targets, {
    opacity: immediate ? [0.7, 1] : [0, 1],
    translateY: immediate ? [0, 0] : [14, 0],
    delay: immediate ? 0 : stagger(65),
    duration: immediate ? 220 : 420,
    ease: "outExpo",
  })
}

const pulseCommand = (root: HomeInstallPanelElement) => {
  if (root._homeInstallReduceMotion) return
  const target = command(root)
  if (!target) return

  animate(target, {
    opacity: [0.45, 1],
    translateY: [8, 0],
    duration: 360,
    ease: "outExpo",
  })
}

export const HomeInstallPanel: Hook = {
  mounted() {
    const root = this.el as HomeInstallPanelElement
    const media = window.matchMedia("(prefers-reduced-motion: reduce)")
    const button = copyButton(root)

    root._homeInstallReduceMotion = media.matches
    root._homeInstallCopyValue = root.dataset.copyValue || ""

    runReveal(root)

    const handleCopy = async () => {
      const value = root.dataset.copyValue?.trim() || ""
      const label = root.dataset.copyLabel?.trim() || "agent"

      if (!value) {
        setFeedback(root, "Nothing to copy.")
        return
      }

      try {
        await navigator.clipboard.writeText(value)
        setFeedback(root, `Copied ${label} line.`)

        if (button) {
          animate(button, {
            scale: [1, 0.97, 1],
            duration: 320,
            ease: "outExpo",
          })
        }

        pulseCommand(root)
      } catch {
        setFeedback(root, "Copy failed. Select the command manually.")
      }
    }

    button?.addEventListener("click", handleCopy)

    root._homeInstallCleanup = () => {
      button?.removeEventListener("click", handleCopy)
    }
  },

  updated() {
    const root = this.el as HomeInstallPanelElement
    const nextValue = root.dataset.copyValue || ""

    if (nextValue !== root._homeInstallCopyValue) {
      root._homeInstallCopyValue = nextValue
      pulseCommand(root)
      setFeedback(root, "")
      runReveal(root, true)
    }
  },

  destroyed() {
    const root = this.el as HomeInstallPanelElement
    root._homeInstallCleanup?.()
  },
}
