import "phoenix_html"

import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

import { installPinnedHeerich } from "../../../packages/regent_ui/assets/js/regent"
import { platformHooks } from "./hooks/index"

const csrfToken = (document.querySelector("meta[name='csrf-token']") as HTMLMetaElement | null)?.content
const themeStorageKey = "phx:theme"
const themeMedia = window.matchMedia("(prefers-color-scheme: dark)")

type ThemeChoice = "light" | "dark" | "system"

function resolveTheme(choice: ThemeChoice): "light" | "dark" {
  if (choice === "system") {
    return themeMedia.matches ? "dark" : "light"
  }

  return choice
}

function readThemeChoice(): ThemeChoice {
  const value = window.localStorage.getItem(themeStorageKey)
  return value === "light" || value === "dark" || value === "system" ? value : "light"
}

function applyTheme(choice: ThemeChoice) {
  document.documentElement.dataset.theme = resolveTheme(choice)
  document.documentElement.dataset.themeChoice = choice
}

function setTheme(choice: ThemeChoice) {
  window.localStorage.setItem(themeStorageKey, choice)
  applyTheme(choice)
}

applyTheme(readThemeChoice())
installPinnedHeerich()

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken || "" },
  hooks: platformHooks,
})

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())
window.addEventListener("storage", (event) => {
  if (event.key !== themeStorageKey) return
  applyTheme(readThemeChoice())
})
themeMedia.addEventListener("change", () => {
  if (readThemeChoice() === "system") {
    applyTheme("system")
  }
})
window.addEventListener("phx:set-theme", (event) => {
  const target = event.target as HTMLElement | null
  const nextTheme = target?.dataset.phxTheme

  if (nextTheme === "light" || nextTheme === "dark" || nextTheme === "system") {
    setTheme(nextTheme)
  }
})

liveSocket.connect()

;(window as Window & { liveSocket?: unknown }).liveSocket = liveSocket

if (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1") {
  window.addEventListener("phx:live_reload:attached", (event) => {
    const reloader = (
      event as CustomEvent<{
        enableServerLogs: () => void
        openEditorAtCaller: (target: EventTarget | null) => void
        openEditorAtDef: (target: EventTarget | null) => void
      }>
    ).detail

    reloader.enableServerLogs()

    let keyDown: string | null = null
    window.addEventListener("keydown", (event) => {
      keyDown = event.key
    })
    window.addEventListener("keyup", () => {
      keyDown = null
    })
    window.addEventListener(
      "click",
      (event) => {
        if (keyDown === "c") {
          event.preventDefault()
          event.stopImmediatePropagation()
          reloader.openEditorAtCaller(event.target)
        } else if (keyDown === "d") {
          event.preventDefault()
          event.stopImmediatePropagation()
          reloader.openEditorAtDef(event.target)
        }
      },
      true,
    )

    ;(window as Window & { liveReloader?: unknown }).liveReloader = reloader
  })
}
