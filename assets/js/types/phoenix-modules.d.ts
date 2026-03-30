declare module "phoenix" {
  export class Socket {
    constructor(endpoint: string, options?: unknown)
  }
}

declare module "phoenix_live_view" {
  export interface HookContext {
    el: HTMLElement
    handleEvent(event: string, callback: (payload: unknown) => void): void
    pushEvent(event: string, payload?: Record<string, unknown>): void
  }

  export type Hook = {
    mounted?(this: HookContext): void | Promise<void>
    updated?(this: HookContext): void
    destroyed?(this: HookContext): void
    disconnected?(this: HookContext): void
    reconnected?(this: HookContext): void
  }

  export type HooksOptions = Record<string, Hook>

  export class LiveSocket {
    constructor(
      path: string,
      socket: unknown,
      options?: {
        longPollFallbackMs?: number
        params?: Record<string, unknown>
        hooks?: HooksOptions
      },
    )

    connect(): void
  }
}
