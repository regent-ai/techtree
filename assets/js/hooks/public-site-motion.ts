import type { Hook, HookContext } from "phoenix_live_view"

import { animate, stagger } from "animejs"

interface PublicSiteElement extends HTMLElement {
  _publicCleanup?: () => void
  _publicHeroMediaMotion?: { cancel: () => unknown }
  _publicReducedMotion?: boolean
  _publicLiveItems?: Map<string, string>
  _publicLiveRects?: Map<string, DOMRect>
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
  Array.from(root.querySelectorAll<HTMLElement>("[data-public-live-item]"))

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
      animate(target, {
        opacity: [0, 1],
        translateY: [12, 0],
        scale: [0.985, 1],
        duration: 360,
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
          duration: 420,
          ease: "outExpo",
        })
      }
    }

    if (previousRevision !== revision) {
      animate(target, {
        scale: [1, 1.012, 1],
        duration: 320,
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
      if (root._publicReducedMotion) {
        stopHeroMedia(root)
      } else {
        animateHeroMedia(root)
      }

      runReveal(root)
    }

    root.addEventListener("click", onCopyClick)
    media.addEventListener("change", onMotionChange)

    runReveal(root)
    pulseButtons(root)
    animateHeroMedia(root)
    rememberLiveItems(root)
    root._publicLiveRects = liveItemRects(root)

    root._publicCleanup = () => {
      root.removeEventListener("click", onCopyClick)
      media.removeEventListener("change", onMotionChange)
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
