import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "animejs"

interface HomeInstallPanelElement extends HTMLElement {
  _homeInstallCleanup?: () => void
  _homeInstallCopyValue?: string
  _homeInstallReduceMotion?: boolean
  _homeInstallCopyTimer?: number
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

const setCopyState = (
  root: HomeInstallPanelElement,
  button: HTMLButtonElement | null,
  state: "success" | "error",
) => {
  const target = feedback(root)
  if (button) button.dataset.copyState = state
  if (target) target.dataset.copyState = state

  if (root._homeInstallCopyTimer) {
    window.clearTimeout(root._homeInstallCopyTimer)
  }

  root._homeInstallCopyTimer = window.setTimeout(() => {
    if (button) delete button.dataset.copyState
    if (target) delete target.dataset.copyState
  }, 1200)
}

const runReveal = (root: HomeInstallPanelElement, immediate = false) => {
  const targets = revealTargets(root)
  if (targets.length === 0) return

  if (root._homeInstallReduceMotion) {
    targets.forEach((target) => {
      target.style.transform = "none"
      target.style.opacity = "1"
    })
    return
  }

  animate(targets, {
    opacity: immediate ? [0.7, 1] : [0, 1],
    translateY: immediate ? [0, 0] : [14, 0],
    delay: immediate ? 0 : stagger(65),
    duration: immediate ? 220 : 420,
    ease: "outExpo",
  })
}

const pulseCommand = (root: HomeInstallPanelElement) => {
  const target = command(root)
  if (!target) return

  if (root._homeInstallReduceMotion) {
    target.style.transform = "none"
    target.style.opacity = "1"
    return
  }

  animate(target, {
    opacity: [0.45, 1],
    translateY: [6, 0],
    duration: 260,
    ease: "outExpo",
  })
}

const runCopySuccessMotion = (
  root: HomeInstallPanelElement,
  button: HTMLButtonElement | null,
  pointerActivated: boolean,
) => {
  const target = feedback(root)

  if (root._homeInstallReduceMotion) {
    if (button) button.style.transform = "none"
    if (target) {
      target.style.transform = "none"
      target.style.opacity = "1"
    }
    return
  }

  if (button && pointerActivated) {
    animate(button, {
      scale: [1, 0.97, 1],
      duration: 180,
      ease: "outExpo",
    })
  }

  if (target) {
    animate(target, {
      opacity: [0.72, 1],
      scale: [0.985, 1.025, 1],
      duration: 220,
      ease: "outExpo",
    })
  }
}

export const HomeInstallPanel: Hook = {
  mounted() {
    const root = this.el as HomeInstallPanelElement
    const media = window.matchMedia("(prefers-reduced-motion: reduce)")
    const button = copyButton(root)

    root._homeInstallReduceMotion = media.matches
    root._homeInstallCopyValue = root.dataset.copyValue || ""

    runReveal(root)

    let pointerActivated = false

    const handlePointerDown = () => {
      pointerActivated = true
    }

    const handleCopy = async () => {
      const value = root.dataset.copyValue?.trim() || ""
      const label = root.dataset.copyLabel?.trim() || "agent"
      const shouldAnimatePress = pointerActivated
      pointerActivated = false

      if (!value) {
        setFeedback(root, "Nothing to copy.")
        setCopyState(root, button, "error")
        return
      }

      try {
        await navigator.clipboard.writeText(value)
        setFeedback(root, `Copied ${label} line. Paste it into your terminal.`)
        setCopyState(root, button, "success")
        runCopySuccessMotion(root, button, shouldAnimatePress)

        pulseCommand(root)
      } catch {
        setFeedback(root, "Copy failed. Select the command manually.")
        setCopyState(root, button, "error")
      }
    }

    button?.addEventListener("pointerdown", handlePointerDown)
    button?.addEventListener("click", handleCopy)

    const handleMotionChange = () => {
      root._homeInstallReduceMotion = media.matches
    }

    if ("addEventListener" in media) {
      media.addEventListener("change", handleMotionChange)
    } else {
      const legacyMedia = media as MediaQueryList & {
        addListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
        removeListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
      }

      legacyMedia.addListener(handleMotionChange)
    }

    root._homeInstallCleanup = () => {
      button?.removeEventListener("pointerdown", handlePointerDown)
      button?.removeEventListener("click", handleCopy)
      if (root._homeInstallCopyTimer) {
        window.clearTimeout(root._homeInstallCopyTimer)
      }
      if ("removeEventListener" in media) {
        media.removeEventListener("change", handleMotionChange)
      } else {
        const legacyMedia = media as MediaQueryList & {
          addListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
          removeListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
        }

        legacyMedia.removeListener(handleMotionChange)
      }
    }
  },

  updated() {
    const root = this.el as HomeInstallPanelElement
    const nextValue = root.dataset.copyValue || ""

    if (nextValue !== root._homeInstallCopyValue) {
      root._homeInstallCopyValue = nextValue
      pulseCommand(root)
      setFeedback(root, "")
    }
  },

  destroyed() {
    const root = this.el as HomeInstallPanelElement
    root._homeInstallCleanup?.()
  },
}
