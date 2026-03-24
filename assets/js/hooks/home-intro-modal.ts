import type { Hook, HookContext } from "phoenix_live_view";

import { animate } from "../../vendor/anime.esm.js";

const COOKIE_NAME = "techtree_home_modal_hidden";
const COOKIE_MAX_AGE_SECONDS = 15_552_000;

type HomeIntroModalHook = HookContext &
  Hook & {
    copiedResetTimer?: number;
    copiedStateTimer?: number;
    forceVisible?: boolean;
    isVisible?: boolean;
    motionPreferenceMedia?: MediaQueryList;
    onDocumentClick?: (event: MouseEvent) => void;
    onDocumentKeydown?: (event: KeyboardEvent) => void;
    onMotionPreferenceChange?: (event: MediaQueryListEvent) => void;
    onPersistChange?: () => void;
    persistInput?: HTMLInputElement | null;
    reduceMotion?: boolean;
    syncVisibility: (animateIn: boolean) => void;
  };

function installCommand(root: HTMLElement): string {
  return root.dataset.installCommand || "pnpm add -g @regentlabs/cli";
}

function rootElement(target: HTMLElement): HTMLElement | null {
  return target.closest<HTMLElement>("#frontpage-home-page");
}

function readCookie(name: string): string | null {
  const prefix = `${name}=`;
  const match = document.cookie
    .split(";")
    .map((part) => part.trim())
    .find((part) => part.startsWith(prefix));

  return match ? decodeURIComponent(match.slice(prefix.length)) : null;
}

function writeCookie(hidden: boolean) {
  if (hidden) {
    document.cookie =
      `${COOKIE_NAME}=1; Path=/; Max-Age=${COOKIE_MAX_AGE_SECONDS}; SameSite=Lax`;
    return;
  }

  document.cookie = `${COOKIE_NAME}=; Path=/; Max-Age=0; SameSite=Lax`;
}

function shouldHideByCookie(): boolean {
  return readCookie(COOKIE_NAME) === "1";
}

function modalCard(target: HTMLElement): HTMLElement | null {
  return target.querySelector<HTMLElement>(".fp-intro-box");
}

function modalRevealTargets(target: HTMLElement): HTMLElement[] {
  return Array.from(
    target.querySelectorAll<HTMLElement>(
      ".fp-intro-kicker, .fp-intro-title, .fp-intro-lead, .fp-intro-command-shell, .fp-intro-actions, .fp-intro-secondary-actions, .fp-intro-persist-row, .fp-intro-side-note",
    ),
  );
}

function feedbackTarget(target: HTMLElement): HTMLElement | null {
  return target.querySelector<HTMLElement>("#frontpage-intro-copy-feedback");
}

function installButton(target: HTMLElement): HTMLElement | null {
  return target.querySelector<HTMLElement>("#frontpage-intro-install");
}

function commandBody(target: HTMLElement): HTMLElement | null {
  return target.querySelector<HTMLElement>(".fp-intro-command-body");
}

function statusDot(target: HTMLElement): HTMLElement | null {
  return target.querySelector<HTMLElement>(".fp-intro-status-dot");
}

function setFeedback(hook: HomeIntroModalHook, message: string) {
  const feedback = feedbackTarget(hook.el as HTMLElement);
  if (!feedback) return;

  feedback.textContent = message;

  if (hook.copiedResetTimer) {
    window.clearTimeout(hook.copiedResetTimer);
  }

  if (!message) return;

  hook.copiedResetTimer = window.setTimeout(() => {
    feedback.textContent = "";
    hook.copiedResetTimer = undefined;
  }, 2200);
}

function pulseInstallButton(hook: HomeIntroModalHook) {
  if (hook.reduceMotion) return;

  const button = installButton(hook.el as HTMLElement);
  if (!button) return;

  animate(button, {
    scale: [1, 1.02, 1],
    translateY: [0, -1, 0],
    duration: 320,
    ease: "outCubic",
  });
}

function pulseCommandBody(hook: HomeIntroModalHook) {
  if (hook.reduceMotion) return;

  const body = commandBody(hook.el as HTMLElement);
  const dot = statusDot(hook.el as HTMLElement);

  if (body) {
    animate(body, {
      translateY: [0, -1, 0],
      boxShadow: [
        "inset 0 1px 0 rgba(255, 255, 255, 0.03)",
        "0 0 0 1px rgba(108, 208, 161, 0.12), 0 0 1.3rem rgba(108, 208, 161, 0.14)",
        "inset 0 1px 0 rgba(255, 255, 255, 0.03)",
      ],
      duration: 420,
      ease: "outCubic",
    });
  }

  if (dot) {
    animate(dot, {
      scale: [1, 1.15, 1],
      backgroundColor: ["#6cd0a1", "#f3bf68", "#6cd0a1"],
      duration: 420,
      ease: "outQuad",
    });
  }
}

function setInstallButtonLabel(hook: HomeIntroModalHook, nextLabel: string) {
  const button = installButton(hook.el as HTMLElement);
  if (!button) return;

  if (!button.dataset.defaultLabel) {
    button.dataset.defaultLabel = button.textContent?.trim() || nextLabel;
  }

  button.textContent = nextLabel;
}

function restoreInstallButtonLabel(hook: HomeIntroModalHook) {
  const button = installButton(hook.el as HTMLElement);
  if (!button) return;

  button.textContent = button.dataset.defaultLabel || "Install in 1 command";
}

async function copyInstallCommand(hook: HomeIntroModalHook) {
  const root = rootElement(hook.el as HTMLElement);
  if (!root) return;

  const command = installCommand(root);

  try {
    await navigator.clipboard.writeText(command);
    (hook.el as HTMLElement).dataset.copied = "true";
    setInstallButtonLabel(hook, "Copied");
    setFeedback(hook, "Copied install command.");
    pulseInstallButton(hook);
    pulseCommandBody(hook);

    if (hook.copiedStateTimer) {
      window.clearTimeout(hook.copiedStateTimer);
    }

    hook.copiedStateTimer = window.setTimeout(() => {
      delete (hook.el as HTMLElement).dataset.copied;
      restoreInstallButtonLabel(hook);
      hook.copiedStateTimer = undefined;
    }, 1400);
  } catch (_error) {
    setFeedback(hook, "Copy failed. Select the command manually.");
  }
}

function persistCheckbox(target: HTMLElement): HTMLInputElement | null {
  return target.querySelector<HTMLInputElement>("#frontpage-intro-persist");
}

function syncPersistCheckbox(hook: HomeIntroModalHook) {
  const input = hook.persistInput || persistCheckbox(hook.el as HTMLElement);
  if (!input) return;

  input.checked = shouldHideByCookie();
  hook.persistInput = input;
}

function runReveal(hook: HomeIntroModalHook) {
  if (hook.reduceMotion) return;

  const card = modalCard(hook.el as HTMLElement);
  const targets = modalRevealTargets(hook.el as HTMLElement);

  if (!card) return;

  card.style.transformOrigin = "center top";

  animate(card, {
    opacity: [0.78, 1],
    translateY: [18, 0],
    scale: [0.97, 1],
    duration: 520,
    ease: "outExpo",
  });

  animate(targets, {
    opacity: [0, 1],
    translateY: [12, 0],
    delay: (_, index) => 60 + index * 36,
    duration: 320,
    ease: "outQuad",
  });
}

function runHide(hook: HomeIntroModalHook) {
  if (hook.reduceMotion) return;

  const card = modalCard(hook.el as HTMLElement);
  if (!card) return;

  animate(card, {
    opacity: [1, 0],
    translateY: [0, 12],
    scale: [1, 0.985],
    duration: 240,
    ease: "inQuad",
  });
}

function enterViaServer(hook: HomeIntroModalHook) {
  hook.pushEvent("enter", {});
}

export const HomeIntroModal: Hook = {
  mounted() {
    const hook = this as HomeIntroModalHook;
    hook.forceVisible = false;
    hook.isVisible = false;
    hook.persistInput = persistCheckbox(this.el as HTMLElement);
    hook.motionPreferenceMedia = window.matchMedia("(prefers-reduced-motion: reduce)");
    hook.reduceMotion = hook.motionPreferenceMedia.matches;

    hook.syncVisibility = (animateIn: boolean) => {
      const modal = hook.el as HTMLElement;
      const root = rootElement(modal);
      if (!root) return;

      const serverOpen = root.dataset.introOpen === "true";
      const cookieHidden = shouldHideByCookie();
      const nextVisible = serverOpen && (!cookieHidden || !!hook.forceVisible);

      syncPersistCheckbox(hook);

      modal.dataset.ready = "true";
      modal.dataset.visible = nextVisible ? "true" : "false";
      modal.setAttribute("aria-hidden", nextVisible ? "false" : "true");

      if (serverOpen && cookieHidden && !hook.forceVisible) {
        enterViaServer(hook);
      }

      if (hook.isVisible !== nextVisible && nextVisible && animateIn) {
        runReveal(hook);
      } else if (hook.isVisible !== nextVisible && !nextVisible) {
        runHide(hook);
      }

      hook.isVisible = nextVisible;
    };

    const onPersistChange = () => {
      const input = hook.persistInput || persistCheckbox(this.el as HTMLElement);
      if (!input) return;

      writeCookie(input.checked);
    };

    hook.onPersistChange = onPersistChange;
    hook.persistInput?.addEventListener("change", onPersistChange);

    const onDocumentClick = (event: MouseEvent) => {
      const target = event.target as HTMLElement | null;
      if (!target) return;

      if (target.closest("#frontpage-reopen-intro")) {
        hook.forceVisible = true;
        return;
      }

      if (target.closest("#frontpage-intro-install")) {
        event.preventDefault();
        void copyInstallCommand(hook);
        return;
      }

      if (target.closest("#frontpage-intro-modal") && target === hook.el) {
        hook.forceVisible = false;
        enterViaServer(hook);
        return;
      }

      if (target.closest("#frontpage-intro-enter")) {
        hook.forceVisible = false;
        syncPersistCheckbox(hook);
      }
    };

    hook.onDocumentClick = onDocumentClick;
    document.addEventListener("click", onDocumentClick);

    const onDocumentKeydown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || !hook.isVisible) return;

      event.preventDefault();
      hook.forceVisible = false;
      enterViaServer(hook);
    };

    hook.onDocumentKeydown = onDocumentKeydown;
    document.addEventListener("keydown", onDocumentKeydown);

    const onMotionPreferenceChange = (event: MediaQueryListEvent) => {
      hook.reduceMotion = event.matches;
    };

    hook.onMotionPreferenceChange = onMotionPreferenceChange;
    hook.motionPreferenceMedia.addEventListener("change", onMotionPreferenceChange);

    hook.syncVisibility(true);
  },

  updated() {
    const hook = this as HomeIntroModalHook;
    hook.syncVisibility(false);
  },

  destroyed() {
    const hook = this as HomeIntroModalHook;

    if (hook.copiedResetTimer) {
      window.clearTimeout(hook.copiedResetTimer);
    }

    if (hook.copiedStateTimer) {
      window.clearTimeout(hook.copiedStateTimer);
    }

    restoreInstallButtonLabel(hook);

    if (hook.persistInput && hook.onPersistChange) {
      hook.persistInput.removeEventListener("change", hook.onPersistChange);
    }

    if (hook.onDocumentClick) {
      document.removeEventListener("click", hook.onDocumentClick);
    }

    if (hook.onDocumentKeydown) {
      document.removeEventListener("keydown", hook.onDocumentKeydown);
    }

    if (hook.motionPreferenceMedia && hook.onMotionPreferenceChange) {
      hook.motionPreferenceMedia.removeEventListener("change", hook.onMotionPreferenceChange);
    }
  },
};
