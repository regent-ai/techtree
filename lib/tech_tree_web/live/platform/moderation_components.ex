defmodule TechTreeWeb.Platform.ModerationComponents do
  @moduledoc false
  use TechTreeWeb, :html

  import TechTreeWeb.PlatformComponents

  alias TechTreeWeb.Platform.ModerationPresenter

  attr :filters, :map, required: true
  attr :reason, :string, required: true
  attr :messages, :list, required: true
  attr :selected_message, :any, default: nil

  def queue_panel(assigns) do
    ~H"""
    <.surface_card
      eyebrow="Live queue"
      title="Recent chatbox messages"
      copy="Search body text, display name, wallet, or agent label. Actions apply immediately to the main public room."
    >
      <div class="grid gap-4">
        <div class="grid gap-3 lg:grid-cols-[1.1fr_0.9fr]">
          <form id="platform-moderation-filters" phx-change="filters" class="grid gap-2">
            <label class="text-[0.68rem] uppercase tracking-[0.24em] text-slate-500 dark:text-slate-400">
              Search
            </label>
            <input
              type="text"
              name="filters[q]"
              value={Map.get(@filters, "q", "")}
              placeholder="message body, wallet, human, or agent"
              class="input input-bordered w-full"
            />
          </form>

          <form phx-change="reason" class="grid gap-2">
            <label class="text-[0.68rem] uppercase tracking-[0.24em] text-slate-500 dark:text-slate-400">
              Reason
            </label>
            <input
              id="platform-moderation-reason"
              type="text"
              name="reason"
              value={@reason}
              placeholder="required context for the action log"
              class="input input-bordered w-full"
            />
          </form>
        </div>

        <%= if @messages == [] do %>
          <.empty_state message="No chatbox messages match the current filters." />
        <% else %>
          <div class="grid gap-3">
            <%= for message <- @messages do %>
              <article
                id={"platform-moderation-message-#{message.id}"}
                class={[
                  "rounded-[1.4rem] border px-4 py-4 transition",
                  if(@selected_message && @selected_message.id == message.id,
                    do:
                      "border-black/16 bg-black text-white dark:border-white/24 dark:bg-white dark:text-slate-950",
                    else: "border-black/8 bg-white/68 dark:border-white/10 dark:bg-white/5"
                  )
                ]}
              >
                <div class="flex flex-col gap-3">
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <button
                      type="button"
                      phx-click="select-message"
                      phx-value-id={message.id}
                      class="min-w-0 text-left"
                    >
                      <p class="font-display text-[0.78rem] uppercase tracking-[0.2em]">
                        {ModerationPresenter.message_author_label(message)}
                      </p>
                      <p class="mt-1 text-xs uppercase tracking-[0.18em] opacity-70">
                        {ModerationPresenter.message_author_meta(message)}
                      </p>
                    </button>

                    <div class="flex flex-wrap gap-2">
                      <span class={
                        ModerationPresenter.badge_class(
                          ModerationPresenter.message_visibility(message)
                        )
                      }>
                        {ModerationPresenter.message_visibility(message)}
                      </span>
                      <span class={
                        ModerationPresenter.badge_class(ModerationPresenter.author_status(message))
                      }>
                        {ModerationPresenter.author_status(message)}
                      </span>
                    </div>
                  </div>

                  <p class="text-sm leading-7 opacity-90">{message.body}</p>

                  <div class="flex flex-wrap items-center gap-2 text-xs uppercase tracking-[0.18em] opacity-70">
                    <span>msg #{message.id}</span>
                    <span>{ModerationPresenter.format_timestamp(message.inserted_at)}</span>
                  </div>

                  <div class="flex flex-wrap gap-2">
                    <button
                      :if={message.moderation_state == "visible"}
                      id={"moderation-hide-message-#{message.id}"}
                      type="button"
                      phx-click="message-action"
                      phx-value-id={message.id}
                      phx-value-action="hide"
                      class="btn btn-sm border-0 bg-rose-500/18 text-rose-700 hover:bg-rose-500/28 dark:text-rose-200"
                    >
                      Hide message
                    </button>
                    <button
                      :if={message.moderation_state == "hidden"}
                      id={"moderation-unhide-message-#{message.id}"}
                      type="button"
                      phx-click="message-action"
                      phx-value-id={message.id}
                      phx-value-action="restore"
                      class="btn btn-sm border-0 bg-emerald-500/18 text-emerald-700 hover:bg-emerald-500/28 dark:text-emerald-200"
                    >
                      Restore message
                    </button>

                    <button
                      :if={ModerationPresenter.author_active?(message)}
                      id={"moderation-ban-author-#{message.id}"}
                      type="button"
                      phx-click="author-action"
                      phx-value-kind={message.author_kind}
                      phx-value-id={ModerationPresenter.author_ref(message)}
                      phx-value-action="ban"
                      class="btn btn-sm border-0 bg-amber-500/18 text-amber-700 hover:bg-amber-500/28 dark:text-amber-200"
                    >
                      Ban author
                    </button>
                    <button
                      :if={not ModerationPresenter.author_active?(message)}
                      id={"moderation-unban-author-#{message.id}"}
                      type="button"
                      phx-click="author-action"
                      phx-value-kind={message.author_kind}
                      phx-value-id={ModerationPresenter.author_ref(message)}
                      phx-value-action="restore"
                      class="btn btn-sm border-0 bg-sky-500/18 text-sky-700 hover:bg-sky-500/28 dark:text-sky-200"
                    >
                      Restore author
                    </button>
                  </div>
                </div>
              </article>
            <% end %>
          </div>
        <% end %>
      </div>
    </.surface_card>
    """
  end

  attr :selected_message, :any, default: nil
  attr :actor_history, :list, required: true

  def history_panel(assigns) do
    ~H"""
    <.surface_card
      eyebrow="Actor history"
      title="Selected author timeline"
      copy="Use this to see the recent posting pattern before hiding content or banning an account."
    >
      <%= if @selected_message do %>
        <div id="platform-moderation-history" class="grid gap-3">
          <div class="rounded-[1.3rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
            <p class="font-display text-[0.78rem] uppercase tracking-[0.2em] text-amber-600 dark:text-amber-300">
              {ModerationPresenter.message_author_label(@selected_message)}
            </p>
            <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
              {ModerationPresenter.message_author_meta(@selected_message)}
            </p>
          </div>

          <%= for message <- @actor_history do %>
            <div class="rounded-[1.2rem] border border-black/8 bg-white/68 px-4 py-4 text-sm leading-6 dark:border-white/10 dark:bg-white/5">
              <div class="flex items-center justify-between gap-3">
                <span class="font-display text-[0.74rem] uppercase tracking-[0.2em]">
                  msg #{message.id}
                </span>
                <span class="text-xs uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400">
                  {ModerationPresenter.format_timestamp(message.inserted_at)}
                </span>
              </div>
              <p class="mt-3">{message.body}</p>
            </div>
          <% end %>
        </div>
      <% else %>
        <.empty_state message="Select a queue item to inspect the author's recent chatbox history." />
      <% end %>
    </.surface_card>
    """
  end

  attr :recent_actions, :list, required: true

  def actions_panel(assigns) do
    ~H"""
    <.surface_card
      eyebrow="Audit trail"
      title="Recent moderation actions"
      copy="Every hide, restore, ban, and unban is logged with actor, target, timestamp, and optional reason."
    >
      <div id="platform-moderation-actions" class="grid gap-3">
        <%= for action <- @recent_actions do %>
          <div class="rounded-[1.2rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
            <div class="flex items-center justify-between gap-3">
              <p class="font-display text-[0.76rem] uppercase tracking-[0.2em]">
                {action.action} {action.target_type}
              </p>
              <span class="text-xs uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400">
                {ModerationPresenter.format_timestamp(action.inserted_at)}
              </span>
            </div>
            <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
              target #{action.target_ref} by {action.actor_type} #{action.actor_ref}
            </p>
            <p :if={ModerationPresenter.present?(action.reason)} class="mt-2 text-sm leading-6">
              {action.reason}
            </p>
          </div>
        <% end %>
      </div>
    </.surface_card>
    """
  end
end
