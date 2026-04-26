import type { Hook } from "phoenix_live_view";

import { animate, stagger } from "animejs";
import { LocalStorage, Privy } from "../../vendor/privy-core.esm.js";
import {
  clearPrivySession,
  syncPrivySession,
  type PrivySessionResponse,
} from "./privy-session";
import {
  labelForUser,
  loginWithPrivyWallet,
  type PrivyLike,
  type PrivyUser,
  requireEthereumProvider,
  signWithConnectedWallet,
} from "./privy-wallet";

const ROOM_HEARTBEAT_MS = 30_000;

interface HomeChatboxElement extends HTMLElement {
  _homeChatboxCleanup?: () => void;
  _homeChatboxSeenKeys?: Set<string>;
  _homeChatboxMounted?: boolean;
  _homeChatboxReduceMotion?: boolean;
  _homeChatboxCurrentTab?: string;
  _homeChatboxHeartbeat?: number;
  _homeChatboxSyncComposerState?: () => void;
}

const chatPane = (root: HTMLElement) =>
  root.closest<HTMLElement>("#frontpage-chat-pane");

const activeChatSection = (root: HTMLElement) =>
  chatPane(root)?.querySelector<HTMLElement>(
    ".fp-chat-section[aria-hidden='false']",
  );

const boolData = (root: HTMLElement, key: string) => root.dataset[key] === "true";

const animateActiveChatSection = (root: HomeChatboxElement) => {
  if (root._homeChatboxReduceMotion) return;

  const section = activeChatSection(root);
  if (!section) return;

  animate(section, {
    opacity: [0.84, 1],
    translateY: [10, 0],
    duration: 260,
    ease: "outExpo",
  });
};

export const HomeChatbox: Hook = {
  mounted() {
    const root = this.el as HomeChatboxElement;
    root._homeChatboxMounted = true;
    const motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const syncMotionPreference = () => {
      root._homeChatboxReduceMotion = motionQuery.matches;
    };

    syncMotionPreference();
    root._homeChatboxCurrentTab = chatPane(root)?.dataset.chatTab || "human";

    const authButton = root.querySelector<HTMLButtonElement>(
      "[data-chatbox-auth]",
    );
    const disconnectButton = root.querySelector<HTMLButtonElement>(
      "[data-chatbox-disconnect]",
    );
    const sendButton = root.querySelector<HTMLButtonElement>(
      "[data-chatbox-send]",
    );
    const input = root.querySelector<HTMLInputElement>("[data-chatbox-input]");
    const state = root.querySelector<HTMLElement>("[data-chatbox-state]");
    const sessionUrl =
      root.dataset.sessionUrl?.trim() || "/api/auth/privy/session";
    const completeUrl = "/api/auth/privy/xmtp/complete";
    const privyAppId = root.dataset.privyAppId?.trim() || "";
    const csrfToken =
      document
        .querySelector<HTMLMetaElement>("meta[name='csrf-token']")
        ?.content?.trim() || "";

    if (!authButton || !disconnectButton || !sendButton || !input || !state) {
      return;
    }

    let currentUser: PrivyUser = null;
    let signingIn = false;
    let sending = false;
    const privy =
      privyAppId.length > 0
        ? (new Privy({
            appId: privyAppId,
            clientId: privyAppId,
            storage: new LocalStorage(),
          }) as unknown as PrivyLike)
        : null;

    const setState = (message: string) => {
      if (!root._homeChatboxMounted || state.textContent === message) return;

      state.textContent = message;
      if (!root._homeChatboxReduceMotion) {
        animate(state, {
          opacity: [0.55, 1],
          translateY: [-3, 0],
          duration: 280,
          ease: "outQuad",
        });
      }
    };

    const syncComposerState = () => {
      if (!root._homeChatboxMounted) return;

      const connected = Boolean(currentUser?.id);
      const joined = boolData(root, "roomJoined");
      const canJoin = boolData(root, "roomCanJoin");
      const canSend = boolData(root, "roomCanSend");
      const pending = boolData(root, "roomPending");
      const draft = input.value.trim();

      authButton.disabled = privy == null || signingIn || pending;
      authButton.textContent = connected
        ? joined
          ? `Disconnect ${labelForUser(currentUser)}`
          : pending
            ? "Check wallet"
            : canJoin
              ? "Join room"
              : `Signed in as ${labelForUser(currentUser)}`
        : "Sign in";

      disconnectButton.disabled = privy == null || signingIn || sending;
      disconnectButton.hidden = !connected || joined;

      input.disabled = !canSend || sending;
      sendButton.disabled = !canSend || sending || draft.length === 0;
      sendButton.textContent = sending ? "Sending..." : "Send to public room";
    };

    root._homeChatboxSyncComposerState = syncComposerState;

    const ensureSessionReady = async (
      user: PrivyUser,
      allowInteractiveCompletion: boolean,
    ): Promise<PrivySessionResponse | null> => {
      if (!privy || !user?.id) return null;

      const session = await syncPrivySession(privy, user, {
        csrfToken,
        sessionUrl,
        completeUrl,
        allowInteractiveCompletion,
      });

      if (session.xmtp?.status === "signature_required") {
        setState("Check your wallet to finish room setup.");
        return session;
      }

      setState("Signed in. Join when you want to post.");
      return session;
    };

    const refreshUser = async (allowInteractiveCompletion = false) => {
      if (!privy) {
        currentUser = null;
        setState("Sign-in is not available right now.");
        syncComposerState();
        return;
      }

      try {
        const result = await privy.user.get();
        if (!root._homeChatboxMounted) return;

        currentUser = ((result?.user as PrivyUser) || null)?.id
          ? (result?.user as PrivyUser)
          : null;

        if (currentUser?.id) {
          await ensureSessionReady(currentUser, allowInteractiveCompletion);
        }
      } catch (error) {
        console.error("Home chat sign-in refresh failed", error);
        setState(
          error instanceof Error
            ? error.message
            : "Sign-in could not be checked.",
        );
      } finally {
        syncComposerState();
      }
    };

    const beginLogin = async () => {
      if (!privy || signingIn || sending) return;

      signingIn = true;
      setState("Check your wallet to continue.");
      syncComposerState();

      try {
        const provider = await requireEthereumProvider();
        await loginWithPrivyWallet(privy, provider);
        await refreshUser(true);
        if (!boolData(root, "serverSignedIn")) {
          window.location.reload();
          return;
        }
        this.pushEvent("frontpage_chat_join", {});
      } catch (error) {
        console.error("Home chat sign-in failed", error);
        setState(error instanceof Error ? error.message : "Sign-in failed.");
      } finally {
        signingIn = false;
        syncComposerState();
      }
    };

    const joinRoom = async () => {
      if (!currentUser?.id || signingIn || sending) return;

      signingIn = true;
      setState("Opening your room seat...");
      syncComposerState();

      try {
        await ensureSessionReady(currentUser, true);
        if (!boolData(root, "serverSignedIn")) {
          window.location.reload();
          return;
        }
        this.pushEvent("frontpage_chat_join", {});
      } catch (error) {
        console.error("Home chat join failed", error);
        setState(
          error instanceof Error ? error.message : "We could not join the room.",
        );
      } finally {
        signingIn = false;
        syncComposerState();
      }
    };

    const disconnect = async () => {
      if (!privy || !currentUser?.id) return;

      try {
        await privy.auth.logout({ userId: currentUser.id });
        await clearPrivySession(sessionUrl, csrfToken);
        currentUser = null;
        input.value = "";
        setState("Signed out. You can still read the room.");
        if (boolData(root, "serverSignedIn")) {
          window.location.reload();
          return;
        }
      } catch (error) {
        console.error("Home chat sign-out failed", error);
        currentUser = null;
        setState(error instanceof Error ? error.message : "Sign-out failed.");
      } finally {
        syncComposerState();
      }
    };

    const toggleAuth = async () => {
      if (!privy) {
        setState("Sign-in is not available right now.");
        return;
      }

      if (!currentUser?.id) {
        await beginLogin();
        return;
      }

      if (!boolData(root, "roomJoined") && boolData(root, "roomCanJoin")) {
        await joinRoom();
        return;
      }

      await disconnect();
    };

    const sendMessage = async () => {
      if (!boolData(root, "roomCanSend") || sending) return;

      const body = input.value.trim();
      if (body.length === 0) {
        syncComposerState();
        return;
      }

      sending = true;
      setState("Sending your update...");
      syncComposerState();

      this.pushEvent("frontpage_chat_send", { body });
      input.value = "";
      sending = false;
      syncComposerState();

      if (!root._homeChatboxReduceMotion) {
        animate(sendButton, {
          scale: [1, 0.96, 1],
          duration: 380,
          ease: "outExpo",
        });
      }
    };

    const observeFeed = (initial: boolean) => {
      const seenKeys = root._homeChatboxSeenKeys ?? new Set<string>();
      const entries = Array.from(
        root.querySelectorAll<HTMLElement>("[data-chatbox-entry]"),
      );
      const newEntries = entries.filter((entry) => {
        const key = entry.dataset.messageKey || entry.id;
        if (seenKeys.has(key)) return false;

        seenKeys.add(key);
        return true;
      });

      root._homeChatboxSeenKeys = seenKeys;

      if (!initial && newEntries.length > 0 && !root._homeChatboxReduceMotion) {
        animate(newEntries, {
          opacity: [0, 1],
          translateY: [16, 0],
          scale: [0.97, 1],
          delay: stagger(70),
          duration: 620,
          ease: "outExpo",
        });
      }
    };

    this.handleEvent("xmtp:sign-request", async (payload) => {
      const { request_id, signature_text, wallet_address } = payload as {
        request_id: string;
        signature_text: string;
        wallet_address?: string | null;
      };

      try {
        setState("Check your wallet to finish joining.");
        const provider = await requireEthereumProvider();
        const { signature } = await signWithConnectedWallet(
          provider,
          String(signature_text ?? ""),
          typeof wallet_address === "string" ? wallet_address : null,
        );

        setState("Joining room...");
        this.pushEvent("frontpage_chat_join_signature_signed", {
          request_id,
          signature,
        });
      } catch (error) {
        const message =
          error instanceof Error && error.message
            ? error.message
            : "We could not finish joining this room.";

        setState(message);
        this.pushEvent("frontpage_chat_join_signature_failed", { message });
      }
    });

    const handleInput = () => syncComposerState();
    const handleAuthClick = () => void toggleAuth();
    const handleDisconnectClick = () => void disconnect();
    const handleSendClick = () => void sendMessage();
    const handleInputKeydown = (event: KeyboardEvent) => {
      if (event.key !== "Enter" || event.shiftKey) return;
      event.preventDefault();
      void sendMessage();
    };

    input.addEventListener("input", handleInput);
    input.addEventListener("keydown", handleInputKeydown);
    authButton.addEventListener("click", handleAuthClick);
    disconnectButton.addEventListener("click", handleDisconnectClick);
    sendButton.addEventListener("click", handleSendClick);

    if ("addEventListener" in motionQuery) {
      motionQuery.addEventListener("change", syncMotionPreference);
    }

    root._homeChatboxHeartbeat = window.setInterval(() => {
      this.pushEvent("frontpage_chat_heartbeat", {});
    }, ROOM_HEARTBEAT_MS);

    syncComposerState();
    observeFeed(true);

    void (async () => {
      if (privy) {
        await privy.initialize();
        await refreshUser();
      } else {
        setState("Sign-in is not available right now.");
      }
    })();

    root._homeChatboxCleanup = () => {
      root._homeChatboxMounted = false;

      if (root._homeChatboxHeartbeat) {
        window.clearInterval(root._homeChatboxHeartbeat);
      }

      delete root._homeChatboxSyncComposerState;

      input.removeEventListener("input", handleInput);
      input.removeEventListener("keydown", handleInputKeydown);
      authButton.removeEventListener("click", handleAuthClick);
      disconnectButton.removeEventListener("click", handleDisconnectClick);
      sendButton.removeEventListener("click", handleSendClick);

      if ("removeEventListener" in motionQuery) {
        motionQuery.removeEventListener("change", syncMotionPreference);
      }
    };
  },

  updated() {
    const root = this.el as HomeChatboxElement;
    root._homeChatboxSeenKeys = root._homeChatboxSeenKeys ?? new Set<string>();
    root._homeChatboxSyncComposerState?.();

    if (root._homeChatboxCurrentTab !== chatPane(root)?.dataset.chatTab) {
      root._homeChatboxCurrentTab = chatPane(root)?.dataset.chatTab || "human";
      animateActiveChatSection(root);
    }

    const entries = Array.from(
      root.querySelectorAll<HTMLElement>("[data-chatbox-entry]"),
    );
    const newEntries = entries.filter((entry) => {
      const key = entry.dataset.messageKey || entry.id;
      if (root._homeChatboxSeenKeys?.has(key)) return false;
      root._homeChatboxSeenKeys?.add(key);
      return true;
    });

    if (newEntries.length > 0 && !root._homeChatboxReduceMotion) {
      animate(newEntries, {
        opacity: [0, 1],
        translateY: [16, 0],
        scale: [0.97, 1],
        delay: stagger(70),
        duration: 620,
        ease: "outExpo",
      });
    }
  },

  destroyed() {
    const root = this.el as HomeChatboxElement;
    root._homeChatboxCleanup?.();
  },
};
