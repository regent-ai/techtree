import type { Hook, HookContext, HooksOptions } from "phoenix_live_view";

type LazyHookRegistry = Partial<HooksOptions>;

type LazyHookWindow = Window & {
  __techTreeLazyHooks?: LazyHookRegistry;
  __techTreeLazyAssets?: Record<string, Promise<void>>;
};

type LazyAssetScript = HTMLScriptElement & {
  readyState?: string;
  dataset: DOMStringMap & {
    techTreeLazyAsset?: string;
    techTreeLazyLoaded?: string;
  };
};

type LazyHookContext = HookContext & {
  __lazyDelegate?: Hook | null;
  __lazyLoading?: Promise<Hook | null>;
  __lazyDestroyed?: boolean;
  __lazyFallback?: HTMLElement | null;
};

type RuntimeHook = Hook & {
  updated?: (this: LazyHookContext) => void;
  destroyed?: (this: LazyHookContext) => void;
  disconnected?: (this: LazyHookContext) => void;
  reconnected?: (this: LazyHookContext) => void;
};

type LazyHookOptions = {
  shouldLoad?: (context: LazyHookContext) => boolean;
};

type LazyHookElement = HTMLElement & {
  dataset: DOMStringMap & {
    lazyFallbackMessage?: string;
    lazyHookState?: string;
  };
};

function lazyWindow(): LazyHookWindow {
  return window as LazyHookWindow;
}

export function registerLazyHooks(hooks: LazyHookRegistry) {
  const globalWindow = lazyWindow();
  globalWindow.__techTreeLazyHooks = {
    ...(globalWindow.__techTreeLazyHooks || {}),
    ...hooks,
  };
}

function hookRegistry(): LazyHookRegistry {
  return lazyWindow().__techTreeLazyHooks || {};
}

function loadAsset(assetPath: string): Promise<void> {
  const globalWindow = lazyWindow();
  const pending = globalWindow.__techTreeLazyAssets?.[assetPath];

  if (pending) {
    return pending;
  }

  const promise = new Promise<void>((resolve, reject) => {
    const selector = `script[data-tech-tree-lazy-asset="${assetPath}"]`;
    const existing = document.querySelector<LazyAssetScript>(selector);

    if (existing) {
      if (existing.dataset.techTreeLazyLoaded === "true" || existing.readyState === "complete") {
        resolve();
        return;
      }

      existing.addEventListener("load", () => resolve(), { once: true });
      existing.addEventListener(
        "error",
        () => reject(new Error(`failed to load lazy asset ${assetPath}`)),
        { once: true },
      );
      return;
    }

    const script = document.createElement("script") as LazyAssetScript;
    script.defer = true;
    script.src = assetPath;
    script.dataset.techTreeLazyAsset = assetPath;
    script.addEventListener("load", () => {
      script.dataset.techTreeLazyLoaded = "true";
      resolve();
    }, { once: true });
    script.addEventListener(
      "error",
      () => reject(new Error(`failed to load lazy asset ${assetPath}`)),
      { once: true },
    );
    document.head.appendChild(script);
  });

  globalWindow.__techTreeLazyAssets = {
    ...(globalWindow.__techTreeLazyAssets || {}),
    [assetPath]: promise,
  };

  return promise;
}

function fallbackMessageFor(element: LazyHookElement, hookName: string): string {
  return (
    element.dataset.lazyFallbackMessage ||
    `Unable to start ${hookName}. Reload the page or verify the related browser configuration.`
  );
}

function ensureFallbackElement(context: LazyHookContext, hookName: string): HTMLElement {
  if (context.__lazyFallback && context.__lazyFallback.isConnected) {
    return context.__lazyFallback;
  }

  const root = context.el as LazyHookElement;
  const existing = root.querySelector<HTMLElement>("[data-tech-tree-lazy-fallback]");

  if (existing) {
    context.__lazyFallback = existing;
    return existing;
  }

  root.classList.add("tt-lazy-hook-host");

  const fallback = document.createElement("div");
  fallback.setAttribute("data-tech-tree-lazy-fallback", hookName);
  fallback.setAttribute("role", "status");
  fallback.className = "tt-lazy-hook-fallback";
  fallback.hidden = true;
  fallback.textContent = fallbackMessageFor(root, hookName);
  root.prepend(fallback);
  context.__lazyFallback = fallback;
  return fallback;
}

function setLazyHookState(context: LazyHookContext, state: "idle" | "loading" | "ready" | "error") {
  const root = context.el as LazyHookElement;
  root.dataset.lazyHookState = state;
  root.setAttribute("aria-busy", state == "loading" ? "true" : "false");
}

function showLazyHookFallback(context: LazyHookContext, hookName: string) {
  const fallback = ensureFallbackElement(context, hookName);
  fallback.hidden = false;
  setLazyHookState(context, "error");
}

function hideLazyHookFallback(context: LazyHookContext) {
  context.__lazyFallback?.setAttribute("hidden", "");
  setLazyHookState(context, "ready");
}

async function ensureLazyHook(hookName: string, assetPath: string): Promise<Hook | null> {
  const existing = hookRegistry()[hookName];

  if (existing) {
    return existing;
  }

  await loadAsset(assetPath);

  const resolved = hookRegistry()[hookName];

  if (!resolved) {
    throw new Error(`lazy hook "${hookName}" did not register after loading ${assetPath}`);
  }

  return resolved;
}

function callLifecycle(
  hook: RuntimeHook | null | undefined,
  lifecycle: "updated" | "destroyed" | "disconnected" | "reconnected",
  context: LazyHookContext,
) {
  const handler = hook?.[lifecycle];

  if (typeof handler === "function") {
    handler.call(context);
  }
}

function startLazyHookLoad(
  context: LazyHookContext,
  hookName: string,
  assetPath: string,
): Promise<Hook | null> {
  setLazyHookState(context, "loading");
  context.__lazyLoading =
    context.__lazyLoading ||
    ensureLazyHook(hookName, assetPath)
      .then((resolvedHook) => {
        context.__lazyDelegate = resolvedHook;
        hideLazyHookFallback(context);

        if (!context.__lazyDestroyed && typeof resolvedHook?.mounted === "function") {
          resolvedHook.mounted.call(context);
        }

        return resolvedHook;
      })
      .catch((error) => {
        console.error(`Failed to initialize lazy hook "${hookName}"`, error);
        showLazyHookFallback(context, hookName);
        return null;
      });

  return context.__lazyLoading;
}

export function createLazyHook(
  hookName: string,
  assetPath: string,
  options: LazyHookOptions = {},
): Hook {
  const shouldLoad = options.shouldLoad || (() => true);
  const hook: RuntimeHook = {
    mounted(this: LazyHookContext) {
      this.__lazyDestroyed = false;
      setLazyHookState(this, "idle");

      if (shouldLoad(this)) {
        startLazyHookLoad(this, hookName, assetPath);
      }
    },

    updated(this: LazyHookContext) {
      if (!this.__lazyDelegate && shouldLoad(this)) {
        startLazyHookLoad(this, hookName, assetPath);
        return;
      }

      callLifecycle(this.__lazyDelegate as RuntimeHook | null | undefined, "updated", this);
    },

    destroyed(this: LazyHookContext) {
      this.__lazyDestroyed = true;
      callLifecycle(this.__lazyDelegate as RuntimeHook | null | undefined, "destroyed", this);
      this.__lazyFallback?.remove();
      this.__lazyFallback = null;
    },

    disconnected(this: LazyHookContext) {
      callLifecycle(
        this.__lazyDelegate as RuntimeHook | null | undefined,
        "disconnected",
        this,
      );
    },

    reconnected(this: LazyHookContext) {
      callLifecycle(
        this.__lazyDelegate as RuntimeHook | null | undefined,
        "reconnected",
        this,
      );
    },
  };

  return hook as Hook;
}
