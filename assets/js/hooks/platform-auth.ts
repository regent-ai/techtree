import type { Hook } from "phoenix_live_view"

import { animate } from "../../vendor/anime.esm.js"
import { LocalStorage, Privy } from "../../vendor/privy-core.esm.js"
import { clearPrivySession, syncPrivySession } from "./privy-session"
import {
  labelForUser,
  loginWithPrivyWallet,
  type PrivyLike,
  type PrivyUser,
  requireEthereumProvider,
} from "./privy-wallet"

type PlatformAuthElement = HTMLElement & {
  _platformAuthCleanup?: () => void
  _platformAuthMounted?: boolean
  _platformAuthAbortControllers?: Set<AbortController>
}

export const PlatformAuth: Hook = {
  mounted() {
    const root = this.el as PlatformAuthElement
    root._platformAuthMounted = true
    root._platformAuthAbortControllers = new Set<AbortController>()
    const toggle = root.querySelector<HTMLButtonElement>("[data-platform-auth-action='toggle']")
    const state = root.querySelector<HTMLElement>("[data-platform-auth-state]")
    const appId = root.dataset.privyAppId?.trim() || ""
    const csrfToken =
      document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content?.trim() || ""

    if (!toggle || !state) {
      return
    }

    const sessionUrl = "/api/auth/privy/session"
    const privy =
      appId.length > 0
        ? (new Privy({ appId, clientId: appId, storage: new LocalStorage() }) as unknown as PrivyLike)
        : null

    let currentUser: PrivyUser = null
    let busy = false

    const setState = (message: string) => {
      if (!root._platformAuthMounted) return
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
      if (!root._platformAuthMounted) return
      toggle.disabled = busy || privy == null
      toggle.textContent = busy
        ? "Working..."
        : currentUser?.id
          ? `Disconnect ${labelForUser(currentUser)}`
          : "Connect wallet"
    }

    const refreshUser = async () => {
      if (!privy) {
        currentUser = null
        setState("Wallet sign-in is not available right now.")
        syncControls()
        return
      }

      try {
        const result = await privy.user.get()
        if (!root._platformAuthMounted) return
        currentUser = ((result?.user as PrivyUser) || null)?.id ? (result?.user as PrivyUser) : null

        if (currentUser?.id) {
          await syncPrivySession(privy, currentUser, {
            csrfToken,
            sessionUrl,
          })
          setState("Connected")
        } else {
          setState("Idle")
        }
      } catch (error) {
        if (!root._platformAuthMounted) return
        console.error("platform auth refresh failed", error)
        currentUser = null
        setState(error instanceof Error ? error.message : "Wallet sign-in could not be checked.")
      } finally {
        syncControls()
      }
    }

    const beginLogin = async () => {
      if (!privy || busy) return

      busy = true
      syncControls()
      setState("Check your wallet to continue.")

      try {
        const provider = await requireEthereumProvider()
        await loginWithPrivyWallet(privy, provider)
        await refreshUser()
      } catch (error) {
        console.error("platform auth login failed", error)
        setState(error instanceof Error ? error.message : "Wallet sign-in failed.")
      } finally {
        busy = false
        syncControls()
      }
    }

    const disconnect = async () => {
      if (!privy || !currentUser?.id || busy) return

      busy = true
      syncControls()
      setState("Disconnecting")

      try {
        await clearPrivySession(sessionUrl, csrfToken)
        await privy.auth.logout({ userId: currentUser.id })
        currentUser = null
        setState("Idle")
      } catch (error) {
        console.error("platform auth logout failed", error)
        setState(error instanceof Error ? error.message : "Disconnect failed.")
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
      root._platformAuthMounted = false
      root._platformAuthAbortControllers?.forEach((controller) => controller.abort())
      root._platformAuthAbortControllers?.clear()
      toggle.removeEventListener("click", onToggle)
    }

    void (async () => {
      if (privy) {
        await privy.initialize()
        await refreshUser()
      } else {
        syncControls()
        setState("Wallet sign-in is not available right now.")
      }
    })()
  },

  destroyed() {
    const root = this.el as PlatformAuthElement
    root._platformAuthCleanup?.()
  },
}
