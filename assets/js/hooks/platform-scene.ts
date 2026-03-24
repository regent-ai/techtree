import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"

type PlatformSceneElement = HTMLElement & {
  _platformSceneReady?: boolean
}

function sceneTargets(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>("section, article, .platform-panel")).filter(
    (target) => target !== root && target.dataset.platformSceneDone !== "1",
  )
}

export const PlatformScene: Hook = {
  mounted() {
    const root = this.el as PlatformSceneElement
    const targets = sceneTargets(root)

    targets.forEach((target) => {
      target.dataset.platformSceneDone = "1"
    })

    if (targets.length === 0) {
      root._platformSceneReady = true
      return
    }

    animate(targets, {
      opacity: [0, 1],
      translateY: [18, 0],
      duration: 560,
      delay: stagger(70, { start: 40 }),
      ease: "outCubic",
    })

    root._platformSceneReady = true
  },

  updated() {
    const root = this.el as PlatformSceneElement
    const targets = sceneTargets(root)

    if (!root._platformSceneReady || targets.length === 0) {
      return
    }

    targets.forEach((target) => {
      target.dataset.platformSceneDone = "1"
    })

    animate(targets, {
      opacity: [0, 1],
      translateY: [14, 0],
      duration: 420,
      delay: stagger(55),
      ease: "outQuad",
    })
  },
}
