import type { Hook } from "phoenix_live_view"

import { animate } from "../../vendor/anime.esm.js"
import { Privy, LocalStorage } from "../../vendor/privy-core.esm.js"

const PROVIDER_STORAGE_KEY = "techtree:platform:privy:oauth-provider"

type PrivyUser =
  | {
      id?: string
      email?: { address?: string }
      linked_accounts?: Array<{ type?: string; address?: string }>
    }
  | null

type PlatformAuthElement = HTMLElement & {
  _platformAuthCleanup?: () => void
}

function userLabel(user: PrivyUser): string {
  if (!user) return "guest"
  return user.email?.address || user.id || "connected"
}

function walletForUser(user: PrivyUser): string | null {
  const wallet = user?.linked_accounts?.find((account) => account?.address)
  return wallet?.address || null
}

export const PlatformAuth: Hook = {
  mounted() {
    const root = this.el as PlatformAuthElement
    const toggle = root.querySelector<HTMLButtonElement>("[data-platform-auth-action='toggle']")
    const state = root.querySelector<HTMLElement>("[data-platform-auth-state]")
    const appId = root.dataset.privyAppId?.trim() || ""
    const csrfToken =
      document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content?.trim() || ""

    if (!toggle || !state) {
      return
    }

    const sessionUrl = "/api/platform/auth/privy/session"
    const privy =
      appId.length > 0
        ? new Privy({ appId, clientId: appId, storage: new LocalStorage() })
        : null

    let currentUser: PrivyUser = null
    let busy = false

    const setState = (message: string) => {
      if (state.textContent === message) return
      state.textContent = message
      animate(state, {
        opacity: [0.55, 1],
        translateY: [-2, 0],
        duration: 240,
        ease: "outQuad",
      })
    }

    const syncControls = () => {
      toggle.disabled = busy || privy == null
      toggle.textContent = busy
        ? "Working..."
        : currentUser?.id
          ? `Disconnect ${userLabel(currentUser)}`
          : "Privy Login"
    }

    const syncSession = async (user: PrivyUser) => {
      if (!privy || !user?.id) return

      const token = await privy.getAccessToken()
      if (!token) return

      await fetch(sessionUrl, {
        method: "POST",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
          ...(csrfToken ? { "x-csrf-token": csrfToken } : {}),
        },
        credentials: "same-origin",
        body: JSON.stringify({
          display_name: userLabel(user),
          wallet_address: walletForUser(user),
        }),
      })
    }

    const clearSession = async () => {
      await fetch(sessionUrl, {
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
        setState("Privy unavailable")
        syncControls()
        return
      }

      try {
        const result = await privy.user.get()
        currentUser = ((result?.user as PrivyUser) || null)?.id ? (result?.user as PrivyUser) : null

        if (currentUser?.id) {
          await syncSession(currentUser)
          setState("connected")
        } else {
          setState("idle")
        }
      } catch (error) {
        console.error("platform auth refresh failed", error)
        currentUser = null
        setState("session error")
      } finally {
        syncControls()
      }
    }

    const completeOAuthFlow = async () => {
      if (!privy) return

      const provider = window.localStorage.getItem(PROVIDER_STORAGE_KEY)
      const url = new URL(window.location.href)
      const code = url.searchParams.get("code")
      const oauthState = url.searchParams.get("state")

      if (!provider || !code || !oauthState) {
        return
      }

      busy = true
      syncControls()
      setState("finishing login")

      try {
        await privy.auth.oauth.loginWithCode(code, oauthState, provider)
        url.searchParams.delete("code")
        url.searchParams.delete("state")
        url.searchParams.delete("provider")
        window.history.replaceState({}, document.title, url.toString())
      } catch (error) {
        console.error("platform auth oauth completion failed", error)
        setState("oauth error")
      } finally {
        window.localStorage.removeItem(PROVIDER_STORAGE_KEY)
        busy = false
      }
    }

    const beginLogin = async () => {
      if (!privy || busy) return

      busy = true
      syncControls()
      setState("redirecting")

      try {
        const redirectUri = new URL(window.location.href)
        redirectUri.searchParams.delete("code")
        redirectUri.searchParams.delete("state")
        redirectUri.searchParams.delete("provider")

        const result = await privy.auth.oauth.generateURL("google", redirectUri.toString())
        window.localStorage.setItem(PROVIDER_STORAGE_KEY, "google")
        window.location.assign(result.url)
      } catch (error) {
        console.error("platform auth login failed", error)
        busy = false
        setState("login error")
        syncControls()
      }
    }

    const disconnect = async () => {
      if (!privy || !currentUser?.id || busy) return

      busy = true
      syncControls()
      setState("disconnecting")

      try {
        await clearSession()
        await privy.auth.logout({ userId: currentUser.id })
        currentUser = null
        setState("idle")
      } catch (error) {
        console.error("platform auth logout failed", error)
        setState("logout error")
      } finally {
        busy = false
        syncControls()
      }
    }

    const onToggle = async () => {
      if (currentUser?.id) {
        await disconnect()
        return
      }

      await beginLogin()
    }

    toggle.addEventListener("click", onToggle)

    root._platformAuthCleanup = () => {
      toggle.removeEventListener("click", onToggle)
    }

    void (async () => {
      if (privy) {
        await privy.initialize()
        await completeOAuthFlow()
      }

      await refreshUser()
    })()
  },

  destroyed() {
    const root = this.el as PlatformAuthElement
    root._platformAuthCleanup?.()
  },
}
