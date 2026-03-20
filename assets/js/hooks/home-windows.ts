import type { Hook, HookContext } from "phoenix_live_view";

import { animate } from "../../vendor/anime.esm.js";
import {
  type AnimationHandle,
  clamp,
  pauseMotion,
  readBool,
} from "./home-shared";

type PanelSide = "agent" | "human";

type PanelFrame = {
  left: number;
  top: number;
  width: number;
  height: number;
};

type PanelState = {
  side: PanelSide;
  lastOpenFrame: PanelFrame | null;
  motion: AnimationHandle | null;
  transitioningTo: boolean | null;
};

type WindowSnapshot = {
  agentOpen: boolean;
  humanOpen: boolean;
};

type WindowsHook = HookContext &
  Hook & {
    __activePanelInteraction?: "drag" | "resize" | null;
    __panelStates?: Map<PanelSide, PanelState>;
    __windowsClick?: (event: MouseEvent) => void;
    __windowsPointerDown?: (event: PointerEvent) => void;
    __windowsResize?: () => void;
    __windowSnapshot?: WindowSnapshot;
  };

const panelSides = ["agent", "human"] as const;

function buildWindowSnapshot(el: HTMLElement): WindowSnapshot {
  return {
    agentOpen: readBool(el.dataset.agentOpen),
    humanOpen: readBool(el.dataset.humanOpen),
  };
}

function asPanelSide(value: string | undefined | null): PanelSide | null {
  return value === "agent" || value === "human" ? value : null;
}

function panelOpen(snapshot: WindowSnapshot, side: PanelSide): boolean {
  return side === "agent" ? snapshot.agentOpen : snapshot.humanOpen;
}

function minimizedPanelFrame(side: PanelSide): PanelFrame {
  const inset =
    window.innerWidth <= 540 ? 6 : window.innerWidth <= 820 ? 8 : 12;
  const size =
    window.innerWidth <= 540 ? 68 : window.innerWidth <= 820 ? 76 : 84;

  return {
    left: side === "agent" ? inset : window.innerWidth - inset - size,
    top: window.innerHeight - inset - size,
    width: size,
    height: size,
  };
}

function frameFromRect(rect: DOMRect): PanelFrame {
  return {
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  };
}

function panelFrame(panel: HTMLElement): PanelFrame {
  const styles = window.getComputedStyle(panel);
  const left = Number.parseFloat(styles.left);
  const top = Number.parseFloat(styles.top);
  const width = Number.parseFloat(styles.width);
  const height = Number.parseFloat(styles.height);

  if ([left, top, width, height].every(Number.isFinite)) {
    return { left, top, width, height };
  }

  return frameFromRect(panel.getBoundingClientRect());
}

function clampPanelFrame(frame: PanelFrame): PanelFrame {
  const margin = window.innerWidth <= 540 ? 6 : 10;
  const minWidth =
    window.innerWidth <= 540 ? 220 : window.innerWidth <= 820 ? 240 : 280;
  const minHeight =
    window.innerWidth <= 540 ? 180 : window.innerWidth <= 820 ? 210 : 260;
  const width = clamp(frame.width, minWidth, window.innerWidth - margin * 2);
  const height = clamp(
    frame.height,
    minHeight,
    window.innerHeight - margin * 2,
  );
  const left = clamp(frame.left, margin, window.innerWidth - margin - width);
  const top = clamp(frame.top, margin, window.innerHeight - margin - height);

  return { left, top, width, height };
}

function bindPanelPointerSession(
  hook: WindowsHook,
  onMove: (event: PointerEvent) => void,
) {
  const onEnd = () => {
    window.removeEventListener("pointermove", onMove);
    window.removeEventListener("pointerup", onEnd);
    window.removeEventListener("pointercancel", onEnd);
    hook.__activePanelInteraction = null;
  };

  window.addEventListener("pointermove", onMove);
  window.addEventListener("pointerup", onEnd);
  window.addEventListener("pointercancel", onEnd);
}

function applyPanelFrame(panel: HTMLElement, frame: PanelFrame) {
  panel.style.left = `${frame.left}px`;
  panel.style.top = `${frame.top}px`;
  panel.style.width = `${frame.width}px`;
  panel.style.height = `${frame.height}px`;
  panel.style.right = "auto";
  panel.style.bottom = "auto";
}

function panelElement(root: HTMLElement, side: PanelSide): HTMLElement | null {
  return root.querySelector<HTMLElement>(
    `.fp-panel[data-panel-side="${side}"]`,
  );
}

function ensurePanelState(hook: WindowsHook, side: PanelSide): PanelState {
  if (!hook.__panelStates) {
    hook.__panelStates = new Map();
  }

  const existing = hook.__panelStates.get(side);

  if (existing) return existing;

  const created: PanelState = {
    side,
    lastOpenFrame: null,
    motion: null,
    transitioningTo: null,
  };

  hook.__panelStates.set(side, created);
  return created;
}

function pausePanelMotion(state: PanelState) {
  pauseMotion(state.motion);
  state.motion = null;
}

function syncPanelWindow(
  root: HTMLElement,
  hook: WindowsHook,
  side: PanelSide,
  open: boolean,
) {
  const panel = panelElement(root, side);
  if (!panel) return;

  const state = ensurePanelState(hook, side);

  if (open) {
    const next = clampPanelFrame(state.lastOpenFrame ?? panelFrame(panel));
    state.lastOpenFrame = next;
    applyPanelFrame(panel, next);
  } else {
    applyPanelFrame(panel, minimizedPanelFrame(side));
  }

  panel.style.opacity = "1";
  panel.style.transform = "none";
}

function animatePanelWindow(
  hook: WindowsHook,
  side: PanelSide,
  open: boolean,
  commitServerClose = false,
) {
  const root = hook.el as HTMLElement;
  const panel = panelElement(root, side);
  if (!panel) return;

  const state = ensurePanelState(hook, side);
  pausePanelMotion(state);

  if (open) {
    const start = minimizedPanelFrame(side);
    const target = clampPanelFrame(state.lastOpenFrame ?? panelFrame(panel));
    state.lastOpenFrame = target;
    state.transitioningTo = true;
    applyPanelFrame(panel, start);
    panel.style.transform = "scale(0.82)";
    panel.style.opacity = "0.78";

    animate(panel, {
      scale: [0.82, 1],
      opacity: [0.78, 1],
      duration: 240,
      ease: "outExpo",
    });

    state.motion = animate(start, {
      left: target.left,
      top: target.top,
      width: target.width,
      height: target.height,
      duration: 260,
      ease: "outExpo",
      onBegin: () => {
        panel.style.willChange = "left, top, width, height, transform, opacity";
      },
      onUpdate: () => applyPanelFrame(panel, start),
      onComplete: () => {
        applyPanelFrame(panel, target);
        panel.style.willChange = "";
        panel.style.transform = "none";
        panel.style.opacity = "1";
        state.motion = null;
        state.transitioningTo = null;
      },
    }) as AnimationHandle;

    return;
  }

  const start = clampPanelFrame(state.lastOpenFrame ?? panelFrame(panel));
  const target = minimizedPanelFrame(side);
  state.lastOpenFrame = start;
  state.transitioningTo = false;
  applyPanelFrame(panel, start);

  animate(panel, {
    scale: [1, 0.82],
    opacity: [1, 0.78],
    duration: 200,
    ease: "inQuad",
  });

  state.motion = animate(start, {
    left: target.left,
    top: target.top,
    width: target.width,
    height: target.height,
    duration: 220,
    ease: "inQuad",
    onBegin: () => {
      panel.style.willChange = "left, top, width, height, transform, opacity";
    },
    onUpdate: () => applyPanelFrame(panel, start),
    onComplete: () => {
      applyPanelFrame(panel, target);
      panel.style.willChange = "";
      panel.style.transform = "none";
      panel.style.opacity = "1";
      state.motion = null;

      if (commitServerClose) {
        hook.pushEvent("toggle_panel", { panel: side });
      } else {
        state.transitioningTo = null;
      }
    },
  }) as AnimationHandle;
}

function startDrag(
  hook: WindowsHook,
  panel: HTMLElement,
  side: PanelSide,
  event: PointerEvent,
) {
  if (hook.__activePanelInteraction) return;

  const state = ensurePanelState(hook, side);
  pausePanelMotion(state);
  hook.__activePanelInteraction = "drag";

  const start = clampPanelFrame(panelFrame(panel));
  const originX = event.clientX;
  const originY = event.clientY;

  panel.style.transform = "none";
  panel.style.opacity = "1";
  applyPanelFrame(panel, start);

  const onMove = (moveEvent: PointerEvent) => {
    const next = clampPanelFrame({
      ...start,
      left: start.left + (moveEvent.clientX - originX),
      top: start.top + (moveEvent.clientY - originY),
    });

    state.lastOpenFrame = next;
    applyPanelFrame(panel, next);
  };

  bindPanelPointerSession(hook, onMove);
}

function startResize(
  hook: WindowsHook,
  panel: HTMLElement,
  side: PanelSide,
  event: PointerEvent,
) {
  if (hook.__activePanelInteraction) return;

  const state = ensurePanelState(hook, side);
  pausePanelMotion(state);
  hook.__activePanelInteraction = "resize";

  const start = clampPanelFrame(panelFrame(panel));
  const originX = event.clientX;
  const originY = event.clientY;
  const minWidth =
    window.innerWidth <= 540 ? 220 : window.innerWidth <= 820 ? 240 : 280;
  const minHeight =
    window.innerWidth <= 540 ? 180 : window.innerWidth <= 820 ? 210 : 260;

  panel.style.transform = "none";
  panel.style.opacity = "1";
  applyPanelFrame(panel, start);

  const onMove = (moveEvent: PointerEvent) => {
    const width = clamp(
      start.width - (moveEvent.clientX - originX),
      minWidth,
      window.innerWidth - 20,
    );
    const height = clamp(
      start.height - (moveEvent.clientY - originY),
      minHeight,
      window.innerHeight - 20,
    );
    const next = clampPanelFrame({
      width,
      height,
      left: start.left,
      top: start.top,
    });

    state.lastOpenFrame = next;
    applyPanelFrame(panel, next);
  };

  bindPanelPointerSession(hook, onMove);
}

export const FrontpageWindows: Hook = {
  mounted() {
    const hook = this as WindowsHook;

    hook.__activePanelInteraction = null;
    hook.__windowSnapshot = buildWindowSnapshot(this.el as HTMLElement);

    for (const side of panelSides) {
      syncPanelWindow(
        this.el as HTMLElement,
        hook,
        side,
        panelOpen(hook.__windowSnapshot, side),
      );
    }

    hook.__windowsClick = (event) => {
      const target = event.target as HTMLElement | null;
      if (!target) return;

      const closeButton = target.closest<HTMLElement>("[data-panel-close]");
      if (closeButton) {
        event.preventDefault();
        const side = asPanelSide(
          closeButton.closest<HTMLElement>(".fp-panel")?.dataset.panelSide,
        );
        if (!side) return;

        animatePanelWindow(hook, side, false, true);
        return;
      }

      const restoreButton = target.closest<HTMLElement>("[data-panel-restore]");
      if (restoreButton) {
        event.preventDefault();
        const side = asPanelSide(
          restoreButton.closest<HTMLElement>(".fp-panel")?.dataset.panelSide,
        );
        if (!side) return;

        const state = ensurePanelState(hook, side);
        state.transitioningTo = true;
        hook.pushEvent("toggle_panel", { panel: side });
      }
    };

    hook.__windowsPointerDown = (event) => {
      const target = event.target as HTMLElement | null;
      if (!target) return;

      const panel = target.closest<HTMLElement>(".fp-panel");
      const side = asPanelSide(panel?.dataset.panelSide);

      if (!panel || !side || panel.dataset.panelOpen !== "true") return;
      if (hook.__activePanelInteraction) return;

      if (
        target.closest("[data-panel-close]") ||
        target.closest("[data-panel-restore]")
      )
        return;

      const resizeHandle = target.closest<HTMLElement>(
        "[data-panel-resize-handle]",
      );
      if (resizeHandle) {
        event.preventDefault();
        startResize(hook, panel, side, event);
        return;
      }

      const dragHandle = target.closest<HTMLElement>(
        "[data-panel-drag-handle]",
      );
      if (dragHandle) {
        event.preventDefault();
        startDrag(hook, panel, side, event);
      }
    };

    hook.__windowsResize = () => {
      const snapshot = buildWindowSnapshot(this.el as HTMLElement);

      for (const side of panelSides) {
        syncPanelWindow(
          this.el as HTMLElement,
          hook,
          side,
          panelOpen(snapshot, side),
        );
      }
    };

    this.el.addEventListener("click", hook.__windowsClick);
    this.el.addEventListener("pointerdown", hook.__windowsPointerDown);
    window.addEventListener("resize", hook.__windowsResize);
  },

  updated() {
    const hook = this as WindowsHook;
    const next = buildWindowSnapshot(this.el as HTMLElement);
    const previous = hook.__windowSnapshot;

    if (!previous) {
      hook.__windowSnapshot = next;
      return;
    }

    if (next.agentOpen !== previous.agentOpen) {
      if (next.agentOpen) {
        animatePanelWindow(hook, "agent", true);
      } else if (ensurePanelState(hook, "agent").transitioningTo !== false) {
        animatePanelWindow(hook, "agent", false);
      } else {
        syncPanelWindow(this.el as HTMLElement, hook, "agent", false);
        ensurePanelState(hook, "agent").transitioningTo = null;
      }
    } else {
      syncPanelWindow(this.el as HTMLElement, hook, "agent", next.agentOpen);
    }

    if (next.humanOpen !== previous.humanOpen) {
      if (next.humanOpen) {
        animatePanelWindow(hook, "human", true);
      } else if (ensurePanelState(hook, "human").transitioningTo !== false) {
        animatePanelWindow(hook, "human", false);
      } else {
        syncPanelWindow(this.el as HTMLElement, hook, "human", false);
        ensurePanelState(hook, "human").transitioningTo = null;
      }
    } else {
      syncPanelWindow(this.el as HTMLElement, hook, "human", next.humanOpen);
    }

    hook.__windowSnapshot = next;
  },

  destroyed() {
    const hook = this as WindowsHook;
    hook.__activePanelInteraction = null;

    for (const side of panelSides) {
      pausePanelMotion(ensurePanelState(hook, side));
    }

    if (hook.__windowsClick)
      this.el.removeEventListener("click", hook.__windowsClick);
    if (hook.__windowsPointerDown)
      this.el.removeEventListener("pointerdown", hook.__windowsPointerDown);
    if (hook.__windowsResize)
      window.removeEventListener("resize", hook.__windowsResize);
  },
};
