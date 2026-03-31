import type { Hook } from "phoenix_live_view"

import { animate, stagger } from "../../vendor/anime.esm.js"
import { Privy, LocalStorage } from "../../vendor/privy-core.esm.js"

const PROVIDER_STORAGE_KEY = "techtree:privy:oauth-provider"
const TRANSPORT_POLL_MS = 15_000

type TransportMode = "libp2p" | "local_only" | "degraded"

type TransportStatusPayload = {
  data?: {
    mode?: TransportMode
    ready?: boolean
    peer_count?: number
  }
}

type PrivyUser =
  | {
      id?: string
      email?: { address?: string }
      linked_accounts?: Array<{ type?: string; address?: string }>
    }
  | null

interface HomeChatboxElement extends HTMLElement {
  _homeChatboxCleanup?: () => void
  _homeChatboxSeenKeys?: Set<string>
  _homeChatboxAbortControllers?: Set<AbortController>
  _homeChatboxMounted?: boolean
}

const labelForUser = (user: PrivyUser): string => {
  if (!user) return "guest"
  return user.email?.address || user.id || "connected"
}

const walletForUser = (user: PrivyUser): string | null => {
  const wallet = user?.linked_accounts?.find((account) => account?.address)
  return wallet?.address || null
}

const buildTransportLabel = (payload: NonNullable<TransportStatusPayload["data"]>): string => {
  if (payload.ready) {
    const peerCount = payload.peer_count ?? 0
    return peerCount === 1 ? "1 peer live" : `${peerCount} peers live`
  }

  if (payload.mode === "degraded") {
    return "mesh degraded"
  }

  return "local only"
}

const transportToneClasses: Record<TransportMode | "ready", string[]> = {
  ready: ["border-[var(--fp-accent)]", "bg-[var(--fp-accent)]", "text-black"],
  libp2p: ["border-[var(--fp-accent)]", "bg-[var(--fp-accent)]", "text-black"],
  local_only: ["border-[var(--fp-panel-border)]", "bg-[var(--fp-panel)]", "text-[var(--fp-text)]"],
  degraded: ["border-[var(--color-warning)]", "bg-[var(--fp-chat-human-accent-bg)]", "text-[var(--fp-text)]"],
}

function registerAbortController(root: HomeChatboxElement): AbortController {
  const controller = new AbortController()
  const controllers = root._homeChatboxAbortControllers ?? new Set<AbortController>()
  controllers.add(controller)
  root._homeChatboxAbortControllers = controllers
  return controller
}

function finishAbortController(root: HomeChatboxElement, controller: AbortController) {
  root._homeChatboxAbortControllers?.delete(controller)
}

async function fetchJson<T>(
  root: HomeChatboxElement,
  input: string,
  init: RequestInit,
): Promise<T> {
  const controller = registerAbortController(root)

  try {
    const response = await fetch(input, {
      ...init,
      signal: controller.signal,
    })

    if (!response.ok) {
      throw new Error(await parseErrorMessage(response))
    }

    return (await response.json()) as T
  } finally {
    finishAbortController(root, controller)
  }
}

async function parseErrorMessage(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as {
      error?: { message?: string; code?: string }
      message?: string
    }

    return (
      payload.error?.message ||
      payload.message ||
      payload.error?.code ||
      `request failed (${response.status})`
    )
  } catch {
    return `request failed (${response.status})`
  }
}

export const HomeChatbox: Hook = {
  mounted() {
    const root = this.el as HomeChatboxElement
    root._homeChatboxMounted = true
    root._homeChatboxAbortControllers = new Set<AbortController>()
    const authButton = root.querySelector<HTMLButtonElement>("[data-chatbox-auth]")
    const sendButton = root.querySelector<HTMLButtonElement>("[data-chatbox-send]")
    const input = root.querySelector<HTMLInputElement>("[data-chatbox-input]")
    const state = root.querySelector<HTMLElement>("[data-chatbox-state]")
    const transportBadge = root.querySelector<HTMLElement>("[data-chatbox-transport]")
    const transportStatusUrl = root.dataset.transportStatusUrl?.trim() || "/v1/runtime/transport"
    const postUrl = root.dataset.postUrl?.trim() || "/v1/chatbox/messages"
    const sessionUrl = root.dataset.sessionUrl?.trim() || "/api/platform/auth/privy/session"
    const privyAppId = root.dataset.privyAppId?.trim() || ""
    const csrfToken =
      document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content?.trim() || ""

    if (!authButton || !sendButton || !input || !state || !transportBadge) {
      return
    }

    let currentUser: PrivyUser = null
    let sending = false
    const privy =
      privyAppId.length > 0
        ? new Privy({ appId: privyAppId, clientId: privyAppId, storage: new LocalStorage() })
        : null

    const setState = (message: string) => {
      if (!root._homeChatboxMounted) return
      if (state.textContent === message) return
      state.textContent = message
      animate(state, {
        opacity: [0.55, 1],
        translateY: [-3, 0],
        duration: 280,
        ease: "outQuad",
      })
    }

    const paintTransport = (payload: NonNullable<TransportStatusPayload["data"]>) => {
      if (!root._homeChatboxMounted) return
      const nextLabel = buildTransportLabel(payload)
      const tone = payload.ready ? "ready" : (payload.mode ?? "local_only")
      const nextClasses = transportToneClasses[tone]
      const allClasses = new Set(Object.values(transportToneClasses).flat())

      for (const className of allClasses) {
        transportBadge.classList.remove(className)
      }

      transportBadge.classList.add(...nextClasses)

      if (transportBadge.textContent !== nextLabel) {
        transportBadge.textContent = nextLabel
        animate(transportBadge, {
          scale: [0.9, 1],
          opacity: [0.4, 1],
          duration: 420,
          ease: "outExpo",
        })
      }
    }

    const syncComposerState = () => {
      if (!root._homeChatboxMounted) return
      const connected = Boolean(currentUser?.id)
      const draft = input.value.trim()

      authButton.disabled = privy == null
      authButton.textContent = connected ? `Disconnect ${labelForUser(currentUser)}` : "Connect Privy"

      input.disabled = privy == null || !connected || sending
      sendButton.disabled = privy == null || !connected || sending || draft.length === 0
      sendButton.textContent = sending ? "Writing to webapp chatbox..." : "Send to webapp chatbox"
    }

    const syncSession = async (user: PrivyUser) => {
      if (!privy || !user?.id) return

      const token = await privy.getAccessToken()
      if (!token) return

      await fetchJson<Record<string, never>>(root, sessionUrl, {
        method: "POST",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
          ...(csrfToken ? { "x-csrf-token": csrfToken } : {}),
        },
        credentials: "same-origin",
        body: JSON.stringify({
          display_name: labelForUser(user),
          wallet_address: walletForUser(user),
        }),
      })
    }

    const clearSession = async () => {
      await fetchJson<Record<string, never>>(root, sessionUrl, {
        method: "DELETE",
        headers: {
          accept: "application/json",
          ...(csrfToken ? { "x-csrf-token": csrfToken } : {}),
        },
        credentials: "same-origin",
      })
    }

    const refreshUser = async () => {
      if (!privy) {
        currentUser = null
        setState("Privy is not configured for this environment.")
        syncComposerState()
        return
      }

      try {
        const result = await privy.user.get()
        if (!root._homeChatboxMounted) return
        currentUser = ((result?.user as PrivyUser) || null)?.id ? (result?.user as PrivyUser) : null

        if (currentUser?.id) {
          await syncSession(currentUser)
          setState("Authenticated. Posts write to the public webapp chatbox.")
        } else {
          setState("Connect Privy to post into the public webapp chatbox.")
        }
      } catch (error) {
        currentUser = null
        console.error("Home chatbox Privy refresh failed", error)
        setState("Privy session lookup failed.")
      } finally {
        syncComposerState()
      }
    }

    const completeOAuthFlow = async () => {
      if (!privy) return

      const provider = window.localStorage.getItem(PROVIDER_STORAGE_KEY)
      const url = new URL(window.location.href)
      const code = url.searchParams.get("code")
      const oauthState = url.searchParams.get("state")

      if (!provider || !code || !oauthState) return

      try {
        await privy.auth.oauth.loginWithCode(code, oauthState, provider)
      } catch (error) {
        if (!root._homeChatboxMounted) return
        console.error("Home chatbox Privy OAuth failed", error)
        setState("Privy OAuth handoff failed.")
      } finally {
        window.localStorage.removeItem(PROVIDER_STORAGE_KEY)
        url.searchParams.delete("code")
        url.searchParams.delete("state")
        window.history.replaceState({}, "", url.toString())
      }
    }

    const toggleAuth = async () => {
      if (!privy) {
        setState("Privy is not configured for this environment.")
        return
      }

      try {
        const result = await privy.user.get()
        const user = result?.user as PrivyUser

        if (user?.id) {
          await privy.auth.logout({ userId: user.id })
          await clearSession()
          currentUser = null
          input.value = ""
          setState("Disconnected. Connect Privy to post.")
          syncComposerState()
          return
        }
      } catch {
        currentUser = null
      }

      const redirectUri = window.location.href
      const result = await privy.auth.oauth.generateURL("google", redirectUri)
      window.localStorage.setItem(PROVIDER_STORAGE_KEY, "google")
      setState("Redirecting to Privy...")
      window.location.assign(result.url)
    }

    const sendMessage = async () => {
      if (!privy || !currentUser?.id || sending) return

      const body = input.value.trim()
      if (body.length === 0) {
        syncComposerState()
        return
      }

      sending = true
      setState("Writing canonical row...")
      syncComposerState()

      try {
        const token = await privy.getAccessToken()
        if (!token) {
          throw new Error("Privy access token missing")
        }

        const payload = await fetchJson<{ ok?: boolean }>(root, postUrl, {
          method: "POST",
          headers: {
            accept: "application/json",
            "content-type": "application/json",
            authorization: `Bearer ${token}`,
            ...(csrfToken ? { "x-csrf-token": csrfToken } : {}),
          },
          credentials: "same-origin",
          body: JSON.stringify({
            body,
            client_message_id: crypto.randomUUID(),
          }),
        })
        if (!root._homeChatboxMounted || payload.ok === false) return

        input.value = ""
        setState("Canonical row accepted. Mesh fanout will follow.")
        animate(sendButton, {
          scale: [1, 0.96, 1],
          duration: 380,
          ease: "outExpo",
        })
      } catch (error) {
        setState(error instanceof Error ? error.message : "Unable to post chatbox message.")
      } finally {
        sending = false
        syncComposerState()
      }
    }

    const refreshTransport = async () => {
      try {
        const payload = await fetchJson<TransportStatusPayload>(root, transportStatusUrl, {
          method: "GET",
          headers: { accept: "application/json" },
          credentials: "same-origin",
        })
        if (payload.data?.mode) {
          paintTransport(payload.data)
        }
      } catch (error) {
        if (!root._homeChatboxMounted) return
        transportBadge.textContent = "transport error"
        transportBadge.classList.add("border-[var(--color-error)]", "bg-[var(--color-error)]", "text-[var(--color-error-content)]")
        setState(error instanceof Error ? error.message : "Unable to load transport status.")
      }
    }

    const observeFeed = (initial: boolean) => {
      const seenKeys = root._homeChatboxSeenKeys ?? new Set<string>()
      const entries = Array.from(root.querySelectorAll<HTMLElement>("[data-chatbox-entry]"))
      const newEntries = entries.filter((entry) => {
        const key = entry.dataset.messageKey || entry.id
        if (seenKeys.has(key)) {
          return false
        }

        seenKeys.add(key)
        return true
      })

      root._homeChatboxSeenKeys = seenKeys

      if (!initial && newEntries.length > 0) {
        animate(newEntries, {
          opacity: [0, 1],
          translateY: [16, 0],
          scale: [0.97, 1],
          delay: stagger(70),
          duration: 620,
          ease: "outExpo",
        })
      }
    }

    const handleInput = () => syncComposerState()
    const handleAuthClick = () => void toggleAuth()
    const handleSendClick = () => void sendMessage()
    const handleInputKeydown = (event: KeyboardEvent) => {
      if (event.key !== "Enter" || event.shiftKey) return
      event.preventDefault()
      void sendMessage()
    }

    input.addEventListener("input", handleInput)
    input.addEventListener("keydown", handleInputKeydown)
    authButton.addEventListener("click", handleAuthClick)
    sendButton.addEventListener("click", handleSendClick)

    syncComposerState()
    observeFeed(true)

    const pollId = window.setInterval(() => {
      void refreshTransport()
    }, TRANSPORT_POLL_MS)

    void (async () => {
      if (privy) {
        await privy.initialize()
        await completeOAuthFlow()
        await refreshUser()
      } else {
        syncComposerState()
        setState("Privy is not configured for this environment.")
      }

      await refreshTransport()
    })()

    root._homeChatboxCleanup = () => {
      root._homeChatboxMounted = false
      root._homeChatboxAbortControllers?.forEach((controller) => controller.abort())
      root._homeChatboxAbortControllers?.clear()
      window.clearInterval(pollId)
      input.removeEventListener("input", handleInput)
      input.removeEventListener("keydown", handleInputKeydown)
      authButton.removeEventListener("click", handleAuthClick)
      sendButton.removeEventListener("click", handleSendClick)
    }
  },

  updated() {
    const root = this.el as HomeChatboxElement
    const seenKeys = root._homeChatboxSeenKeys ?? new Set<string>()
    root._homeChatboxSeenKeys = seenKeys

    const entries = Array.from(root.querySelectorAll<HTMLElement>("[data-chatbox-entry]"))
    const newEntries = entries.filter((entry) => {
      const key = entry.dataset.messageKey || entry.id
      if (seenKeys.has(key)) {
        return false
      }

      seenKeys.add(key)
      return true
    })

    if (newEntries.length > 0) {
      animate(newEntries, {
        opacity: [0, 1],
        translateY: [16, 0],
        scale: [0.97, 1],
        delay: stagger(70),
        duration: 620,
        ease: "outExpo",
      })
    }
  },

  destroyed() {
    const root = this.el as HomeChatboxElement
    root._homeChatboxCleanup?.()
  },
}
