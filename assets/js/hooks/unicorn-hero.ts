import type { Hook } from "phoenix_live_view"

type UnicornStudioGlobal = {
  init?: () => void | Promise<void>
  isInitialized?: boolean
}

type UnicornHeroWindow = Window & {
  UnicornStudio?: UnicornStudioGlobal
  __techTreeUnicornStudioLoad?: Promise<void>
}

type UnicornStudioScript = HTMLScriptElement & {
  readyState?: string
  dataset: DOMStringMap & {
    techTreeUnicornLoaded?: string
    techTreeUnicornStudio?: string
  }
}

interface UnicornHeroElement extends HTMLElement {
  _unicornHeroCleanup?: () => void
}

function heroWindow(): UnicornHeroWindow {
  return window as UnicornHeroWindow
}

function setState(root: HTMLElement, state: "idle" | "loading" | "ready" | "error" | "reduced-motion") {
  root.dataset.unicornHeroState = state
}

function existingScript(scriptUrl: string) {
  return Array.from(
    document.querySelectorAll<UnicornStudioScript>("script[data-tech-tree-unicorn-studio='true']"),
  ).find((script) => script.src === scriptUrl)
}

function scriptLoaded(script: UnicornStudioScript) {
  return (
    script.dataset.techTreeUnicornLoaded === "true" ||
    script.readyState === "complete" ||
    typeof heroWindow().UnicornStudio?.init === "function"
  )
}

function loadUnicornStudio(scriptUrl: string): Promise<void> {
  const globalWindow = heroWindow()

  if (typeof globalWindow.UnicornStudio?.init === "function") {
    return Promise.resolve()
  }

  if (globalWindow.__techTreeUnicornStudioLoad) {
    return globalWindow.__techTreeUnicornStudioLoad
  }

  globalWindow.__techTreeUnicornStudioLoad = new Promise<void>((resolve, reject) => {
    const loadedScript = existingScript(scriptUrl)

    if (loadedScript) {
      if (scriptLoaded(loadedScript)) {
        resolve()
        return
      }

      loadedScript.addEventListener("load", () => resolve(), { once: true })
      loadedScript.addEventListener("error", () => reject(new Error("Unable to load homepage scene.")), {
        once: true,
      })
      return
    }

    const script = document.createElement("script")
    script.defer = true
    script.src = scriptUrl
    script.dataset.techTreeUnicornStudio = "true"
    script.addEventListener("load", () => {
      script.dataset.techTreeUnicornLoaded = "true"
      resolve()
    }, { once: true })
    script.addEventListener("error", () => reject(new Error("Unable to load homepage scene.")), {
      once: true,
    })
    document.head.appendChild(script)
  })

  return globalWindow.__techTreeUnicornStudioLoad
}

async function startHero(root: UnicornHeroElement, reducedMotion: MediaQueryList) {
  const scriptUrl = root.dataset.unicornScriptUrl?.trim() || ""
  const projectId = root.dataset.usProject?.trim() || ""

  if (reducedMotion.matches) {
    setState(root, "reduced-motion")
    return
  }

  if (!scriptUrl || !projectId) {
    setState(root, "error")
    return
  }

  if (root.dataset.unicornHeroState === "loading" || root.dataset.unicornHeroState === "ready") {
    return
  }

  setState(root, "loading")

  try {
    await loadUnicornStudio(scriptUrl)
    await heroWindow().UnicornStudio?.init?.()
    setState(root, "ready")
  } catch (error) {
    console.error("Homepage scene failed to start.", error)
    setState(root, "error")
  }
}

function watchMotion(root: UnicornHeroElement, media: MediaQueryList) {
  const handleMotionChange = () => {
    if (media.matches) {
      setState(root, "reduced-motion")
    } else {
      setState(root, "idle")
      void startHero(root, media)
    }
  }

  if ("addEventListener" in media) {
    media.addEventListener("change", handleMotionChange)
    root._unicornHeroCleanup = () => media.removeEventListener("change", handleMotionChange)
    return
  }

  const legacyMedia = media as MediaQueryList & {
    addListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
    removeListener: (listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void) => void
  }

  legacyMedia.addListener(handleMotionChange)
  root._unicornHeroCleanup = () => legacyMedia.removeListener(handleMotionChange)
}

export const UnicornHero: Hook = {
  mounted() {
    const root = this.el as UnicornHeroElement
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")

    setState(root, "idle")
    watchMotion(root, reducedMotion)
    void startHero(root, reducedMotion)
  },

  updated() {
    const root = this.el as UnicornHeroElement
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
    void startHero(root, reducedMotion)
  },

  destroyed() {
    const root = this.el as UnicornHeroElement
    root._unicornHeroCleanup?.()
  },
}
