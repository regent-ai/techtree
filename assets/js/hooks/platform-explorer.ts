import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"

type ExplorerAction = "drilldown" | "return"

interface CancelableAnimation {
  cancel?: () => void
  then?: (callback: () => void) => Promise<unknown>
}

interface ExplorerHook extends Hook {
  pushEvent: (event: string, payload: Record<string, unknown>) => void
}

interface ExplorerState {
  cleanup: (() => void) | null
  gridKey: string
  transitioning: boolean
  motions: CancelableAnimation[]
}

const explorerStates = new WeakMap<HTMLElement, ExplorerState>()

export const PlatformExplorer: Hook = {
  mounted() {
    const root = this.el as HTMLElement
    const hook = this as ExplorerHook
    const state = ensureState(root)

    state.gridKey = root.dataset.gridKey ?? ""
    bindActionListener(root, hook, state)
    revealTiles(root, state, true)
  },

  updated() {
    const root = this.el as HTMLElement
    const state = ensureState(root)
    const nextGridKey = root.dataset.gridKey ?? ""

    if (state.gridKey !== nextGridKey) {
      state.gridKey = nextGridKey
      state.transitioning = false
      revealTiles(root, state, false)
    }
  },

  destroyed() {
    const root = this.el as HTMLElement
    const state = explorerStates.get(root)

    if (!state) return

    cancelMotions(state)
    state.cleanup?.()
    explorerStates.delete(root)
  },
}

function ensureState(root: HTMLElement): ExplorerState {
  let state = explorerStates.get(root)

  if (!state) {
    state = {
      cleanup: null,
      gridKey: "",
      transitioning: false,
      motions: [],
    }

    explorerStates.set(root, state)
  }

  return state
}

function bindActionListener(root: HTMLElement, hook: ExplorerHook, state: ExplorerState) {
  if (state.cleanup) return

  const onClick = (event: Event) => {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>(
      "[data-platform-explorer-action]",
    )

    if (!target || state.transitioning) return

    const action = target.dataset.platformExplorerAction as ExplorerAction | undefined
    if (!action) return

    event.preventDefault()
    event.stopPropagation()

    if (action === "drilldown") {
      const coord = target.dataset.coord
      if (!coord) return

      const selectedTile = findHex(root, coord)
      if (!selectedTile) {
        hook.pushEvent("drilldown", { coord })
        return
      }

      state.transitioning = true

      spiralOut(root, state, selectedTile).then(() => {
        hook.pushEvent("drilldown", { coord })
      })

      return
    }

    state.transitioning = true

    collapseGrid(root, state).then(() => {
      hook.pushEvent("return_level", {})
    })
  }

  root.addEventListener("click", onClick, true)
  state.cleanup = () => root.removeEventListener("click", onClick, true)
}

function revealTiles(root: HTMLElement, state: ExplorerState, initial: boolean) {
  const tiles = listHexes(root)
  if (tiles.length === 0) return

  cancelMotions(state)

  const entryMotion = animate(tiles, {
    opacity: [0, 1],
    scale: initial ? [0.82, 1] : [0.72, 1],
    translateY: initial ? [18, 0] : [32, 0],
    rotate: initial ? [0, 0] : [-12, 0],
    delay: stagger(55, { start: 40 }),
    duration: initial ? 620 : 720,
    ease: "outExpo",
  }) as CancelableAnimation

  const shimmerMotion = animate(tiles, {
    translateY: [
      { to: -4, duration: 1800 },
      { to: 0, duration: 1800 },
    ],
    delay: (_target: unknown, index: number) => index * 42,
    loop: true,
    ease: "inOutSine",
  }) as CancelableAnimation

  state.motions.push(entryMotion, shimmerMotion)
}

async function spiralOut(root: HTMLElement, state: ExplorerState, selectedTile: HTMLElement) {
  cancelMotions(state)

  const tiles = listHexes(root)
  const others = tiles.filter((tile) => tile !== selectedTile)
  const selectedCenter = centerOf(selectedTile)

  if (others.length > 0) {
    const othersMotion = animate(others, {
      opacity: [1, 0],
      scale: [1, 0.3],
      rotate: (target: unknown) => [0, spiralRotation(selectedCenter, centerOf(target as HTMLElement))],
      translateX: (target: unknown) => spiralVector(selectedCenter, centerOf(target as HTMLElement)).x,
      translateY: (target: unknown) => spiralVector(selectedCenter, centerOf(target as HTMLElement)).y,
      delay: stagger(28, { start: 20 }),
      duration: 720,
      ease: "inBack",
    }) as CancelableAnimation

    state.motions.push(othersMotion)
    await waitForMotion(othersMotion)
  }

  const selectedMotion = animate(selectedTile, {
    scale: [1, 1.08, 0.92],
    opacity: [1, 0.16],
    duration: 420,
    ease: "inOutSine",
  }) as CancelableAnimation

  state.motions.push(selectedMotion)
  await waitForMotion(selectedMotion)
}

async function collapseGrid(root: HTMLElement, state: ExplorerState) {
  cancelMotions(state)

  const tiles = listHexes(root)
  if (tiles.length === 0) return

  const motion = animate(tiles, {
    opacity: [1, 0],
    scale: [1, 0.46],
    translateY: [0, 28],
    rotate: (_target: unknown, index: number) => [0, index % 2 === 0 ? 12 : -12],
    delay: stagger(18, { start: 12 }),
    duration: 420,
    ease: "inQuad",
  }) as CancelableAnimation

  state.motions.push(motion)
  await waitForMotion(motion)
}

function cancelMotions(state: ExplorerState) {
  for (const motion of state.motions) {
    motion.cancel?.()
  }

  state.motions = []
}

function waitForMotion(motion: CancelableAnimation) {
  if (typeof motion.then === "function") {
    return motion.then(() => undefined)
  }

  return Promise.resolve()
}

function listHexes(root: HTMLElement): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>("[data-platform-hex]"))
}

function findHex(root: HTMLElement, coord: string): HTMLElement | null {
  return root.querySelector<HTMLElement>(`[data-platform-hex][data-coord="${CSS.escape(coord)}"]`)
}

function centerOf(target: HTMLElement) {
  const rect = target.getBoundingClientRect()

  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  }
}

function spiralVector(origin: { x: number; y: number }, target: { x: number; y: number }) {
  const deltaX = target.x - origin.x
  const deltaY = target.y - origin.y
  const distance = Math.hypot(deltaX, deltaY) || 1
  const angle = Math.atan2(deltaY, deltaX) + Math.PI * 0.8
  const radius = distance * 0.75 + 32

  return {
    x: Math.cos(angle) * radius,
    y: Math.sin(angle) * radius,
  }
}

function spiralRotation(origin: { x: number; y: number }, target: { x: number; y: number }) {
  const deltaX = target.x - origin.x
  const deltaY = target.y - origin.y
  const sign = deltaX + deltaY >= 0 ? 1 : -1

  return sign * 145
}
