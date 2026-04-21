import type { Hook } from "phoenix_live_view";

import { animate, stagger } from "../../vendor/anime.esm.js";
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
} from "./privy-wallet";

const TRANSPORT_POLL_MS = 15_000;

type TransportMode = "libp2p" | "local_only" | "degraded";

type TransportStatusPayload = {
  data?: {
    mode?: TransportMode;
    ready?: boolean;
    peer_count?: number;
  };
};

interface HomeChatboxElement extends HTMLElement {
  _homeChatboxCleanup?: () => void;
  _homeChatboxSeenKeys?: Set<string>;
  _homeChatboxAbortControllers?: Set<AbortController>;
  _homeChatboxMounted?: boolean;
  _homeChatboxReduceMotion?: boolean;
  _homeChatboxCurrentTab?: string;
}

const buildTransportLabel = (
  payload: NonNullable<TransportStatusPayload["data"]>,
): string => {
  if (payload.ready) {
    const peerCount = payload.peer_count ?? 0;
    return peerCount === 1 ? "1 peer live" : `${peerCount} peers live`;
  }

  if (payload.mode === "degraded") {
    return "mesh degraded";
  }

  return "local only";
};

const transportToneClasses: Record<TransportMode | "ready", string[]> = {
  ready: ["border-[var(--fp-accent)]", "bg-[var(--fp-accent)]", "text-black"],
  libp2p: ["border-[var(--fp-accent)]", "bg-[var(--fp-accent)]", "text-black"],
  local_only: [
    "border-[var(--fp-panel-border)]",
    "bg-[var(--fp-panel)]",
    "text-[var(--fp-text)]",
  ],
  degraded: [
    "border-[var(--color-warning)]",
    "bg-[var(--fp-chat-human-accent-bg)]",
    "text-[var(--fp-text)]",
  ],
};

const transportErrorClasses = [
  "border-[var(--color-error)]",
  "bg-[var(--color-error)]",
  "text-[var(--color-error-content)]",
];

const chatPane = (root: HTMLElement) =>
  root.closest<HTMLElement>("#frontpage-chat-pane");

const activeChatSection = (root: HTMLElement) =>
  chatPane(root)?.querySelector<HTMLElement>(
    ".fp-chat-section[aria-hidden='false']",
  );

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

function registerAbortController(root: HomeChatboxElement): AbortController {
  const controller = new AbortController();
  const controllers =
    root._homeChatboxAbortControllers ?? new Set<AbortController>();
  controllers.add(controller);
  root._homeChatboxAbortControllers = controllers;
  return controller;
}

function finishAbortController(
  root: HomeChatboxElement,
  controller: AbortController,
) {
  root._homeChatboxAbortControllers?.delete(controller);
}

async function fetchJson<T>(
  root: HomeChatboxElement,
  input: string,
  init: RequestInit,
): Promise<T> {
  const controller = registerAbortController(root);

  try {
    const response = await fetch(input, {
      ...init,
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(await parseErrorMessage(response));
    }

    return (await response.json()) as T;
  } finally {
    finishAbortController(root, controller);
  }
}

async function parseErrorMessage(response: Response): Promise<string> {
  try {
    const payload = (await response.json()) as {
      error?: { message?: string; code?: string };
      message?: string;
    };

    return (
      payload.error?.message ||
      payload.message ||
      payload.error?.code ||
      `request failed (${response.status})`
    );
  } catch {
    return `request failed (${response.status})`;
  }
}

export const HomeChatbox: Hook = {
  mounted() {
    const root = this.el as HomeChatboxElement;
    root._homeChatboxMounted = true;
    root._homeChatboxAbortControllers = new Set<AbortController>();
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
    const transportBadge = root.querySelector<HTMLElement>(
      "[data-chatbox-transport]",
    );
    const transportStatusUrl =
      root.dataset.transportStatusUrl?.trim() || "/v1/runtime/transport";
    const postUrl = root.dataset.postUrl?.trim() || "/v1/chatbox/messages";
    const sessionUrl =
      root.dataset.sessionUrl?.trim() || "/api/auth/privy/session";
    const completeUrl = "/api/auth/privy/xmtp/complete";
    const privyAppId = root.dataset.privyAppId?.trim() || "";
    const csrfToken =
      document
        .querySelector<HTMLMetaElement>("meta[name='csrf-token']")
        ?.content?.trim() || "";

    if (
      !authButton ||
      !disconnectButton ||
      !sendButton ||
      !input ||
      !state ||
      !transportBadge
    ) {
      return;
    }

    let currentUser: PrivyUser = null;
    let roomReady = false;
    let needsRoomSetup = false;
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
      if (!root._homeChatboxMounted) return;
      if (state.textContent === message) return;
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

    const paintTransport = (
      payload: NonNullable<TransportStatusPayload["data"]>,
    ) => {
      if (!root._homeChatboxMounted) return;
      const nextLabel = buildTransportLabel(payload);
      const tone = payload.ready ? "ready" : (payload.mode ?? "local_only");
      const nextClasses = transportToneClasses[tone];
      const allClasses = new Set([
        ...Object.values(transportToneClasses).flat(),
        ...transportErrorClasses,
      ]);

      for (const className of allClasses) {
        transportBadge.classList.remove(className);
      }

      transportBadge.classList.add(...nextClasses);

      if (transportBadge.textContent !== nextLabel) {
        transportBadge.textContent = nextLabel;
        if (!root._homeChatboxReduceMotion) {
          animate(transportBadge, {
            scale: [0.9, 1],
            opacity: [0.4, 1],
            duration: 420,
            ease: "outExpo",
          });
        }
      }
    };

    const syncComposerState = () => {
      if (!root._homeChatboxMounted) return;
      const connected = Boolean(currentUser?.id);
      const draft = input.value.trim();

      authButton.disabled = privy == null;
      authButton.textContent = connected
        ? needsRoomSetup || !roomReady
          ? "Finish setup"
          : `Disconnect ${labelForUser(currentUser)}`
        : "Connect wallet";
      disconnectButton.disabled = privy == null || sending;
      disconnectButton.hidden = !(connected && (needsRoomSetup || !roomReady));

      input.disabled = privy == null || !connected || !roomReady || sending;
      sendButton.disabled =
        privy == null ||
        !connected ||
        !roomReady ||
        sending ||
        draft.length === 0;
      sendButton.textContent = sending
        ? "Sending to public room..."
        : "Send to public room";
    };

    const applySessionState = (session: PrivySessionResponse) => {
      if (session.xmtp?.status === "signature_required") {
        roomReady = false;
        needsRoomSetup = true;
        setState("Sign one wallet message before you post in the public room.");
        return;
      }

      roomReady = true;
      needsRoomSetup = false;
      setState("Connected. You can post in the public room.");
    };

    const ensureSessionReady = async (
      user: PrivyUser,
      allowInteractiveCompletion: boolean,
    ) => {
      if (!privy || !user?.id) return;

      const session = await syncPrivySession(privy, user, {
        csrfToken,
        sessionUrl,
        completeUrl,
        allowInteractiveCompletion,
      });
      applySessionState(session);
    };

    const refreshUser = async (allowInteractiveCompletion = false) => {
      if (!privy) {
        currentUser = null;
        roomReady = false;
        needsRoomSetup = false;
        setState("Wallet sign-in is not available right now.");
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
        } else {
          roomReady = false;
          needsRoomSetup = false;
          setState("Connect your wallet to post in the public room.");
        }
      } catch (error) {
        console.error("Home chatbox wallet refresh failed", error);
        if (!currentUser?.id) {
          roomReady = false;
          needsRoomSetup = false;
        }
        setState(
          error instanceof Error
            ? error.message
            : "Wallet sign-in could not be checked.",
        );
      } finally {
        syncComposerState();
      }
    };

    const beginLogin = async () => {
      if (!privy || sending) return;

      setState("Check your wallet to continue.");

      try {
        const provider = await requireEthereumProvider();
        await loginWithPrivyWallet(privy, provider);
        await refreshUser(true);
      } catch (error) {
        console.error("Home chatbox wallet sign-in failed", error);
        setState(
          error instanceof Error ? error.message : "Wallet sign-in failed.",
        );
        syncComposerState();
      }
    };

    const finishRoomSetup = async () => {
      if (!currentUser?.id || sending) return;

      setState("Check your wallet to continue.");

      try {
        await ensureSessionReady(currentUser, true);
      } catch (error) {
        console.error("Home chatbox room setup failed", error);
        setState(
          error instanceof Error ? error.message : "We could not finish setup.",
        );
      } finally {
        syncComposerState();
      }
    };

    const disconnect = async () => {
      if (!privy || !currentUser?.id) return;

      try {
        await privy.auth.logout({ userId: currentUser.id });
        await clearPrivySession(sessionUrl, csrfToken);
        currentUser = null;
        roomReady = false;
        needsRoomSetup = false;
        input.value = "";
        setState(
          "Disconnected. Connect your wallet to post in the public room.",
        );
      } catch (error) {
        console.error("Home chatbox logout failed", error);
        currentUser = null;
        roomReady = false;
        needsRoomSetup = false;
        setState(error instanceof Error ? error.message : "Disconnect failed.");
      } finally {
        syncComposerState();
      }
    };

    const toggleAuth = async () => {
      if (!privy) {
        setState("Wallet sign-in is not available right now.");
        return;
      }

      if (currentUser?.id) {
        if (needsRoomSetup || !roomReady) {
          await finishRoomSetup();
          return;
        }

        await disconnect();
        return;
      }

      await beginLogin();
    };

    const sendMessage = async () => {
      if (!privy || !currentUser?.id || !roomReady || sending) return;

      const body = input.value.trim();
      if (body.length === 0) {
        syncComposerState();
        return;
      }

      sending = true;
      setState("Sending your update...");
      syncComposerState();

      try {
        const token = await privy.getAccessToken();
        if (!token) {
          throw new Error(
            "Your sign-in token is missing. Reconnect your wallet and try again.",
          );
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
        });
        if (!root._homeChatboxMounted || payload.ok === false) return;

        input.value = "";
        setState("Posted to the public room.");
        if (!root._homeChatboxReduceMotion) {
          animate(sendButton, {
            scale: [1, 0.96, 1],
            duration: 380,
            ease: "outExpo",
          });
        }
      } catch (error) {
        setState(
          error instanceof Error
            ? error.message
            : "Unable to send your message.",
        );
      } finally {
        sending = false;
        syncComposerState();
      }
    };

    const refreshTransport = async () => {
      try {
        const payload = await fetchJson<TransportStatusPayload>(
          root,
          transportStatusUrl,
          {
            method: "GET",
            headers: { accept: "application/json" },
            credentials: "same-origin",
          },
        );
        if (payload.data?.mode) {
          paintTransport(payload.data);
        }
      } catch (error) {
        if (!root._homeChatboxMounted) return;
        transportBadge.textContent = "status unavailable";
        for (const className of Object.values(transportToneClasses).flat()) {
          transportBadge.classList.remove(className);
        }
        transportBadge.classList.add(...transportErrorClasses);
        setState(
          error instanceof Error
            ? error.message
            : "Unable to load transport status.",
        );
      }
    };

    const observeFeed = (initial: boolean) => {
      const seenKeys = root._homeChatboxSeenKeys ?? new Set<string>();
      const entries = Array.from(
        root.querySelectorAll<HTMLElement>("[data-chatbox-entry]"),
      );
      const newEntries = entries.filter((entry) => {
        const key = entry.dataset.messageKey || entry.id;
        if (seenKeys.has(key)) {
          return false;
        }

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
    } else {
      const legacyMotionQuery = motionQuery as MediaQueryList & {
        addListener: (
          listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void,
        ) => void;
        removeListener: (
          listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void,
        ) => void;
      };

      legacyMotionQuery.addListener(syncMotionPreference);
    }

    syncComposerState();
    observeFeed(true);

    const pollId = window.setInterval(() => {
      void refreshTransport();
    }, TRANSPORT_POLL_MS);

    void (async () => {
      if (privy) {
        await privy.initialize();
        await refreshUser();
      } else {
        syncComposerState();
        setState("Wallet sign-in is not available right now.");
      }

      await refreshTransport();
    })();

    root._homeChatboxCleanup = () => {
      root._homeChatboxMounted = false;
      root._homeChatboxAbortControllers?.forEach((controller) =>
        controller.abort(),
      );
      root._homeChatboxAbortControllers?.clear();
      window.clearInterval(pollId);
      input.removeEventListener("input", handleInput);
      input.removeEventListener("keydown", handleInputKeydown);
      authButton.removeEventListener("click", handleAuthClick);
      disconnectButton.removeEventListener("click", handleDisconnectClick);
      sendButton.removeEventListener("click", handleSendClick);
      if ("removeEventListener" in motionQuery) {
        motionQuery.removeEventListener("change", syncMotionPreference);
      } else {
        const legacyMotionQuery = motionQuery as MediaQueryList & {
          addListener: (
            listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void,
          ) => void;
          removeListener: (
            listener: (this: MediaQueryList, ev: MediaQueryListEvent) => void,
          ) => void;
        };

        legacyMotionQuery.removeListener(syncMotionPreference);
      }
    };
  },

  updated() {
    const root = this.el as HomeChatboxElement;
    const seenKeys = root._homeChatboxSeenKeys ?? new Set<string>();
    root._homeChatboxSeenKeys = seenKeys;

    if (root._homeChatboxCurrentTab !== chatPane(root)?.dataset.chatTab) {
      root._homeChatboxCurrentTab = chatPane(root)?.dataset.chatTab || "human";
      animateActiveChatSection(root);
    }

    const entries = Array.from(
      root.querySelectorAll<HTMLElement>("[data-chatbox-entry]"),
    );
    const newEntries = entries.filter((entry) => {
      const key = entry.dataset.messageKey || entry.id;
      if (seenKeys.has(key)) return false;
      seenKeys.add(key);
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
