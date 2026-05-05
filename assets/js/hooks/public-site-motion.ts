import type { Hook, HookContext } from "phoenix_live_view"

import { animate, stagger } from "animejs"

interface PublicSiteElement extends HTMLElement {
  _publicCleanup?: () => void
  _publicHeroMediaMotion?: { cancel: () => unknown }
  _publicReducedMotion?: boolean
  _publicLiveItems?: Map<string, string>
  _publicLiveRects?: Map<string, DOMRect>
  _publicCopyStateTimer?: number
}

type PublicSiteMotionHook = HookContext &
  Hook & {
    el: PublicSiteElement
  }

const revealTargets = (root: HTMLElement) =>
  Array.from(
    root.querySelectorAll<HTMLElement>("[data-public-reveal]:not([data-public-motion-done='1'])"),
  )

const heroButtons = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>(".tt-public-hero-actions > *"))

const heroOrbs = (root: HTMLElement) =>
  Array.from(root.querySelectorAll<HTMLElement>(".tt-public-hero-video-orb"))

const liveItems = (root: HTMLElement) =>
  Array.from(
    root.querySelectorAll<HTMLElement>(
      [
        "[data-public-live-item]",
        ".tt-public-signal-card",
        ".tt-public-signal-value",
        ".tt-public-room-entry",
        ".tt-public-tree-card",
      ].join(","),
    ),
  )

const liveItemKey = (target: HTMLElement) =>
  target.dataset.publicLiveItem || target.id || target.dataset.messageKey || ""

const liveItemRevision = (target: HTMLElement) =>
  target.dataset.publicLiveRevision || target.textContent?.trim() || ""

const liveItemRects = (root: HTMLElement) => {
  const rects = new Map<string, DOMRect>()

  liveItems(root).forEach((target) => {
    const key = liveItemKey(target)
    if (key) rects.set(key, target.getBoundingClientRect())
  })

  return rects
}

const setFeedback = (root: HTMLElement, selector: string | undefined, message: string) => {
  if (!selector) return
  const target = root.querySelector<HTMLElement>(selector)
  if (!target) return
  target.textContent = message
}

const copyValueFromButton = (button: HTMLElement) =>
  button.dataset.copyValue?.trim() || button.textContent?.trim() || ""

const setCopyState = (
  root: PublicSiteElement,
  button: HTMLElement,
  state: "success" | "error",
) => {
  button.dataset.copyState = state

  const feedbackSelector = button.dataset.copyFeedback
  const feedbackTarget = feedbackSelector
    ? root.querySelector<HTMLElement>(feedbackSelector)
    : null

  if (feedbackTarget) {
    feedbackTarget.dataset.copyState = state
  }

  if (root._publicCopyStateTimer) {
    window.clearTimeout(root._publicCopyStateTimer)
  }

  root._publicCopyStateTimer = window.setTimeout(() => {
    delete button.dataset.copyState
    if (feedbackTarget) {
      delete feedbackTarget.dataset.copyState
    }
  }, 1200)
}

const runCopySuccessMotion = (
  root: PublicSiteElement,
  button: HTMLElement,
  pointerActivated: boolean,
) => {
  const feedbackSelector = button.dataset.copyFeedback
  const feedbackTarget = feedbackSelector
    ? root.querySelector<HTMLElement>(feedbackSelector)
    : null

  if (root._publicReducedMotion) {
    button.style.transform = "none"
    if (feedbackTarget) {
      feedbackTarget.style.transform = "none"
      feedbackTarget.style.opacity = "1"
    }
    return
  }

  if (pointerActivated) {
    animate(button, {
      scale: [1, 0.97, 1],
      duration: 180,
      ease: "outExpo",
    })
  }

  if (feedbackTarget) {
    animate(feedbackTarget, {
      opacity: [0.72, 1],
      scale: [0.985, 1.025, 1],
      duration: 220,
      ease: "outExpo",
    })
  }
}

const flashLiveTarget = (root: PublicSiteElement, target: HTMLElement) => {
  const host =
    target instanceof HTMLTableRowElement
      ? target.querySelector<HTMLElement>("td, th")
      : target

  if (!host) return

  host.classList.add("tt-public-live-motion-target")

  if (root._publicReducedMotion) {
    target.style.transform = "none"
    target.style.opacity = "1"
    return
  }

  const flash = document.createElement("span")
  flash.className = "tt-public-live-flash"
  flash.setAttribute("aria-hidden", "true")
  host.appendChild(flash)

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
    translateY: [16, 0],
    delay: stagger(56),
    duration: 420,
    ease: "outExpo",
  })
}

const rememberLiveItems = (root: PublicSiteElement) => {
  const current = new Map<string, string>()

  liveItems(root).forEach((target) => {
    const key = liveItemKey(target)
    if (key) current.set(key, liveItemRevision(target))
  })

  root._publicLiveItems = current
}

const runLiveItemMotion = (root: PublicSiteElement) => {
  const previousItems = root._publicLiveItems || new Map<string, string>()
  const previousRects = root._publicLiveRects || new Map<string, DOMRect>()
  const nextItems = new Map<string, string>()

  liveItems(root).forEach((target) => {
    const key = liveItemKey(target)
    if (!key) return

    const revision = liveItemRevision(target)
    const previousRevision = previousItems.get(key)
    const previousRect = previousRects.get(key)
    const nextRect = target.getBoundingClientRect()

    nextItems.set(key, revision)

    if (root._publicReducedMotion) {
      target.style.transform = "none"
      target.style.opacity = "1"
      return
    }

    if (!previousItems.has(key)) {
      flashLiveTarget(root, target)
      animate(target, {
        opacity: [0, 1],
        translateY: [8, 0],
        scale: [0.99, 1],
        duration: 260,
        ease: "outExpo",
      })

      return
    }

    if (previousRect) {
      const deltaX = previousRect.left - nextRect.left
      const deltaY = previousRect.top - nextRect.top

      if (Math.abs(deltaX) > 1 || Math.abs(deltaY) > 1) {
        animate(target, {
          translateX: [deltaX, 0],
          translateY: [deltaY, 0],
          duration: 260,
          ease: "outExpo",
        })
      }
    }

    if (previousRevision !== revision) {
      flashLiveTarget(root, target)
      animate(target, {
        color: [getComputedStyle(target).color, "rgb(36, 118, 68)", getComputedStyle(target).color],
        scale: [1, 1.01, 1],
        duration: 260,
        ease: "outCubic",
      })
    }
  })

  root._publicLiveItems = nextItems
  root._publicLiveRects = liveItemRects(root)
}

const pulseButtons = (root: PublicSiteElement) => {
  if (root._publicReducedMotion) return

  const targets = heroButtons(root)
  if (targets.length === 0) return

  animate(targets, {
    translateY: [6, 0],
    opacity: [0, 1],
    delay: stagger(40, { start: 100 }),
    duration: 240,
    ease: "outExpo",
  })
}

const animateHeroMedia = (root: PublicSiteElement) => {
  if (root._publicReducedMotion) return
  if (root._publicHeroMediaMotion) return

  const targets = heroOrbs(root)
  if (targets.length === 0) return

  root._publicHeroMediaMotion = animate(targets, {
    translateY: (_target: unknown, index: number) => (index % 2 === 0 ? [0, -10, 0] : [0, 10, 0]),
    translateX: (_target: unknown, index: number) => (index % 2 === 0 ? [0, 6, 0] : [0, -6, 0]),
    scale: [1, 1.03, 1],
    opacity: [0.6, 1, 0.6],
    delay: stagger(150),
    duration: 3600,
    ease: "inOutSine",
    loop: true,
  }) as { cancel: () => unknown }
}

const stopHeroMedia = (root: PublicSiteElement) => {
  root._publicHeroMediaMotion?.cancel()
  delete root._publicHeroMediaMotion

  heroOrbs(root).forEach((target) => {
    target.style.transform = ""
    target.style.opacity = ""
  })
}

export const PublicSiteMotion = {
  mounted(this: PublicSiteMotionHook) {
    const root = this.el as PublicSiteElement
    const media = window.matchMedia("(prefers-reduced-motion: reduce)")
    root._publicReducedMotion = media.matches

    const onPointerDown = (event: Event) => {
      const target = event.target as HTMLElement | null
      const button = target?.closest<HTMLElement>("[data-copy-button]")
      if (button) {
        button.dataset.copyPointer = "true"
      }
    }

    const onCopyClick = async (event: Event) => {
      const target = event.target as HTMLElement | null
      const button = target?.closest<HTMLElement>("[data-copy-button]")
      if (!button) return

      const pointerActivated = button.dataset.copyPointer === "true"
      delete button.dataset.copyPointer

      const value = copyValueFromButton(button)

      if (!value) {
        setFeedback(root, button.dataset.copyFeedback, "Nothing to copy yet.")
        setCopyState(root, button, "error")
        return
      }

      try {
        await navigator.clipboard.writeText(value)
        setFeedback(root, button.dataset.copyFeedback, "Copied.")
        setCopyState(root, button, "success")
        runCopySuccessMotion(root, button, pointerActivated)
      } catch {
        setFeedback(root, button.dataset.copyFeedback, "Copy failed. Select the text manually.")
        setCopyState(root, button, "error")
      }
    }

    const onMotionChange = () => {
      root._publicReducedMotion = media.matches
      if (root._publicReducedMotion) {
        stopHeroMedia(root)
      } else {
        animateHeroMedia(root)
      }

      runReveal(root)
    }

    root.addEventListener("pointerdown", onPointerDown)
    root.addEventListener("click", onCopyClick)
    media.addEventListener("change", onMotionChange)

    runReveal(root)
    pulseButtons(root)
    animateHeroMedia(root)
    rememberLiveItems(root)
    root._publicLiveRects = liveItemRects(root)

    root._publicCleanup = () => {
      root.removeEventListener("pointerdown", onPointerDown)
      root.removeEventListener("click", onCopyClick)
      media.removeEventListener("change", onMotionChange)
      if (root._publicCopyStateTimer) {
        window.clearTimeout(root._publicCopyStateTimer)
      }
      stopHeroMedia(root)
    }
  },

  updated(this: PublicSiteMotionHook) {
    const root = this.el as PublicSiteElement
    runReveal(root)
    runLiveItemMotion(root)
  },

  beforeUpdate(this: PublicSiteMotionHook) {
    const root = this.el as PublicSiteElement
    root._publicLiveRects = liveItemRects(root)
  },

  destroyed(this: PublicSiteMotionHook) {
    const root = this.el as PublicSiteElement
    root._publicCleanup?.()
  },
} as Hook & { beforeUpdate(this: PublicSiteMotionHook): void }
