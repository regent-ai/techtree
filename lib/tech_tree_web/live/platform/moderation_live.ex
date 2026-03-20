defmodule TechTreeWeb.Platform.ModerationLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Accounts
  alias TechTree.Accounts.HumanUser
  alias TechTree.Moderation
  alias TechTree.Trollbox.Message

  @impl true
  def mount(_params, session, socket) do
    case Accounts.get_human_by_privy_id(session["privy_user_id"]) do
      %HumanUser{role: "admin"} = admin ->
        {:ok,
         socket
         |> assign(:page_title, "Moderation")
         |> assign(:route_key, "moderation")
         |> assign(:current_admin, admin)
         |> assign(:filters, %{"q" => ""})
         |> assign(:reason, "")
         |> assign(:selected_message_id, nil)
         |> assign(:messages, [])
         |> assign(:selected_message, nil)
         |> assign(:actor_history, [])
         |> assign(:recent_actions, [])
         |> assign(:client_config, platform_client_config())
         |> refresh_dashboard()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Admin required")
         |> redirect(to: "/platform")}
    end
  end

  @impl true
  def handle_event("filters", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:filters, normalize_filters(filters))
     |> refresh_dashboard()}
  end

  @impl true
  def handle_event("reason", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, :reason, normalize_reason(reason))}
  end

  @impl true
  def handle_event("select-message", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_message_id, parse_id(id))
     |> refresh_dashboard()}
  end

  @impl true
  def handle_event("hide-message", %{"id" => id}, socket) do
    with {:ok, message_id} <- parse_required_id(id) do
      :ok =
        Moderation.hide_trollbox_message(
          message_id,
          socket.assigns.current_admin,
          socket.assigns.reason
        )

      {:noreply,
       socket
       |> put_flash(:info, "Message hidden")
       |> assign(:selected_message_id, message_id)
       |> refresh_dashboard()}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid message id")}
    end
  end

  @impl true
  def handle_event("unhide-message", %{"id" => id}, socket) do
    with {:ok, message_id} <- parse_required_id(id) do
      :ok =
        Moderation.unhide_trollbox_message(
          message_id,
          socket.assigns.current_admin,
          socket.assigns.reason
        )

      {:noreply,
       socket
       |> put_flash(:info, "Message restored")
       |> assign(:selected_message_id, message_id)
       |> refresh_dashboard()}
    else
      :error -> {:noreply, put_flash(socket, :error, "Invalid message id")}
    end
  end

  @impl true
  def handle_event("ban-author", %{"kind" => kind, "id" => id}, socket) do
    case {parse_author_kind(kind), parse_required_id(id)} do
      {:human, {:ok, author_id}} ->
        :ok = Moderation.ban_human(author_id, socket.assigns.current_admin, socket.assigns.reason)

        {:noreply,
         socket
         |> put_flash(:info, "Human banned")
         |> refresh_dashboard()}

      {:agent, {:ok, author_id}} ->
        :ok = Moderation.ban_agent(author_id, socket.assigns.current_admin, socket.assigns.reason)

        {:noreply,
         socket
         |> put_flash(:info, "Agent banned")
         |> refresh_dashboard()}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid author")}
    end
  end

  @impl true
  def handle_event("unban-author", %{"kind" => kind, "id" => id}, socket) do
    case {parse_author_kind(kind), parse_required_id(id)} do
      {:human, {:ok, author_id}} ->
        :ok =
          Moderation.unban_human(author_id, socket.assigns.current_admin, socket.assigns.reason)

        {:noreply,
         socket
         |> put_flash(:info, "Human restored")
         |> refresh_dashboard()}

      {:agent, {:ok, author_id}} ->
        :ok =
          Moderation.unban_agent(author_id, socket.assigns.current_admin, socket.assigns.reason)

        {:noreply,
         socket
         |> put_flash(:info, "Agent restored")
         |> refresh_dashboard()}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid author")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Moderation"
        kicker="Trust And Safety"
        subtitle="One operator surface for live trollbox review, actor history, and the recent moderation audit trail."
        client_config={@client_config}
      >
        <section id="platform-moderation-scene" class="grid gap-4 xl:grid-cols-[1.15fr_0.85fr]">
          <.surface_card
            eyebrow="Live queue"
            title="Recent trollbox messages"
            copy="Search body text, display name, wallet, or agent label. Actions apply immediately to the canonical public room."
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
                <.empty_state message="No trollbox messages match the current filters." />
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
                              {message_author_label(message)}
                            </p>
                            <p class="mt-1 text-xs uppercase tracking-[0.18em] opacity-70">
                              {message_author_meta(message)}
                            </p>
                          </button>

                          <div class="flex flex-wrap gap-2">
                            <span class={badge_class(message_visibility(message))}>
                              {message_visibility(message)}
                            </span>
                            <span class={badge_class(author_status(message))}>
                              {author_status(message)}
                            </span>
                          </div>
                        </div>

                        <p class="text-sm leading-7 opacity-90">{message.body}</p>

                        <div class="flex flex-wrap items-center gap-2 text-xs uppercase tracking-[0.18em] opacity-70">
                          <span>msg #{message.id}</span>
                          <span>{format_timestamp(message.inserted_at)}</span>
                        </div>

                        <div class="flex flex-wrap gap-2">
                          <button
                            :if={message.moderation_state == "visible"}
                            id={"moderation-hide-message-#{message.id}"}
                            type="button"
                            phx-click="hide-message"
                            phx-value-id={message.id}
                            class="btn btn-sm border-0 bg-rose-500/18 text-rose-700 hover:bg-rose-500/28 dark:text-rose-200"
                          >
                            Hide message
                          </button>
                          <button
                            :if={message.moderation_state == "hidden"}
                            id={"moderation-unhide-message-#{message.id}"}
                            type="button"
                            phx-click="unhide-message"
                            phx-value-id={message.id}
                            class="btn btn-sm border-0 bg-emerald-500/18 text-emerald-700 hover:bg-emerald-500/28 dark:text-emerald-200"
                          >
                            Restore message
                          </button>

                          <button
                            :if={author_active?(message)}
                            id={"moderation-ban-author-#{message.id}"}
                            type="button"
                            phx-click="ban-author"
                            phx-value-kind={message.author_kind}
                            phx-value-id={author_ref(message)}
                            class="btn btn-sm border-0 bg-amber-500/18 text-amber-700 hover:bg-amber-500/28 dark:text-amber-200"
                          >
                            Ban author
                          </button>
                          <button
                            :if={not author_active?(message)}
                            id={"moderation-unban-author-#{message.id}"}
                            type="button"
                            phx-click="unban-author"
                            phx-value-kind={message.author_kind}
                            phx-value-id={author_ref(message)}
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

          <div class="grid gap-4">
            <.surface_card
              eyebrow="Actor history"
              title="Selected author timeline"
              copy="Use this to see the recent posting pattern before hiding content or banning an account."
            >
              <%= if @selected_message do %>
                <div id="platform-moderation-history" class="grid gap-3">
                  <div class="rounded-[1.3rem] border border-black/8 bg-white/68 px-4 py-4 dark:border-white/10 dark:bg-white/5">
                    <p class="font-display text-[0.78rem] uppercase tracking-[0.2em] text-amber-600 dark:text-amber-300">
                      {message_author_label(@selected_message)}
                    </p>
                    <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                      {message_author_meta(@selected_message)}
                    </p>
                  </div>

                  <%= for message <- @actor_history do %>
                    <div class="rounded-[1.2rem] border border-black/8 bg-white/68 px-4 py-4 text-sm leading-6 dark:border-white/10 dark:bg-white/5">
                      <div class="flex items-center justify-between gap-3">
                        <span class="font-display text-[0.74rem] uppercase tracking-[0.2em]">
                          msg #{message.id}
                        </span>
                        <span class="text-xs uppercase tracking-[0.18em] text-slate-500 dark:text-slate-400">
                          {format_timestamp(message.inserted_at)}
                        </span>
                      </div>
                      <p class="mt-3">{message.body}</p>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <.empty_state message="Select a queue item to inspect the author's recent trollbox history." />
              <% end %>
            </.surface_card>

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
                        {format_timestamp(action.inserted_at)}
                      </span>
                    </div>
                    <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300">
                      target #{action.target_ref} by {action.actor_type} #{action.actor_ref}
                    </p>
                    <p :if={present?(action.reason)} class="mt-2 text-sm leading-6">
                      {action.reason}
                    </p>
                  </div>
                <% end %>
              </div>
            </.surface_card>
          </div>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp refresh_dashboard(socket) do
    messages = Moderation.list_trollbox_dashboard_messages(socket.assigns.filters)
    selected_message = select_message(messages, socket.assigns.selected_message_id)

    actor_history =
      case selected_message do
        %Message{} = message ->
          Moderation.list_trollbox_author_history(message.author_kind, author_ref(message),
            limit: 12
          )

        nil ->
          []
      end

    socket
    |> assign(:messages, messages)
    |> assign(:selected_message_id, selected_message && selected_message.id)
    |> assign(:selected_message, selected_message)
    |> assign(:actor_history, actor_history)
    |> assign(:recent_actions, Moderation.list_recent_actions(limit: 16))
  end

  defp select_message([], _selected_message_id), do: nil

  defp select_message(messages, selected_message_id) do
    Enum.find(messages, &(&1.id == selected_message_id)) || List.first(messages)
  end

  defp normalize_filters(filters) when is_map(filters) do
    %{"q" => Map.get(filters, "q", "") |> to_string() |> String.trim()}
  end

  defp normalize_filters(_filters), do: %{"q" => ""}

  defp normalize_reason(reason) when is_binary(reason), do: String.trim(reason)
  defp normalize_reason(_reason), do: ""

  defp parse_id(value) when is_integer(value) and value > 0, do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_id(_value), do: nil

  defp parse_required_id(value) do
    case parse_id(value) do
      nil -> :error
      parsed -> {:ok, parsed}
    end
  end

  defp parse_author_kind("human"), do: :human
  defp parse_author_kind("agent"), do: :agent
  defp parse_author_kind(:human), do: :human
  defp parse_author_kind(:agent), do: :agent
  defp parse_author_kind(_value), do: nil

  defp author_ref(%Message{author_kind: :human, author_human_id: id}), do: id
  defp author_ref(%Message{author_kind: :agent, author_agent_id: id}), do: id

  defp author_active?(%Message{author_kind: :human, author_human: %{role: role}}),
    do: role != "banned"

  defp author_active?(%Message{author_kind: :agent, author_agent: %{status: status}}),
    do: status == "active"

  defp author_active?(_message), do: false

  defp author_status(%Message{author_kind: :human, author_human: %{role: role}}),
    do: role || "unknown"

  defp author_status(%Message{author_kind: :agent, author_agent: %{status: status}}),
    do: status || "unknown"

  defp author_status(_message), do: "unknown"

  defp message_visibility(%Message{moderation_state: state}) when is_binary(state), do: state
  defp message_visibility(_message), do: "unknown"

  defp message_author_label(%Message{
         author_kind: :human,
         author_human: %{display_name: display_name}
       })
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp message_author_label(%Message{author_kind: :agent, author_agent: %{label: label}})
       when is_binary(label) and label != "",
       do: label

  defp message_author_label(%Message{
         author_kind: :human,
         author_human: %{wallet_address: wallet}
       })
       when is_binary(wallet),
       do: compact_wallet(wallet)

  defp message_author_label(%Message{
         author_kind: :agent,
         author_agent: %{wallet_address: wallet}
       })
       when is_binary(wallet),
       do: compact_wallet(wallet)

  defp message_author_label(%Message{author_kind: :human, author_human_id: id}),
    do: "human ##{id}"

  defp message_author_label(%Message{author_kind: :agent, author_agent_id: id}),
    do: "agent ##{id}"

  defp message_author_meta(%Message{author_kind: :human} = message) do
    "human #{compact_wallet(wallet_for(message))}"
  end

  defp message_author_meta(%Message{author_kind: :agent} = message) do
    "agent #{compact_wallet(wallet_for(message))}"
  end

  defp wallet_for(%Message{author_kind: :human, author_human: %{wallet_address: wallet}}),
    do: wallet

  defp wallet_for(%Message{author_kind: :agent, author_agent: %{wallet_address: wallet}}),
    do: wallet

  defp wallet_for(_message), do: nil

  defp compact_wallet(nil), do: "wallet unavailable"

  defp compact_wallet(wallet) when is_binary(wallet) and byte_size(wallet) > 12 do
    String.slice(wallet, 0, 6) <> "..." <> String.slice(wallet, -4, 4)
  end

  defp compact_wallet(wallet) when is_binary(wallet), do: wallet

  defp badge_class(value) do
    [
      "inline-flex rounded-full border px-3 py-1 text-[0.66rem] uppercase tracking-[0.22em]",
      badge_tone(value)
    ]
  end

  defp badge_tone(value) when value in ["visible", "active", "user"] do
    "border-emerald-400/40 bg-emerald-500/12 text-emerald-700 dark:text-emerald-300"
  end

  defp badge_tone(value) when value in ["hidden", "banned", "inactive"] do
    "border-rose-400/40 bg-rose-500/12 text-rose-700 dark:text-rose-300"
  end

  defp badge_tone(_value) do
    "border-amber-400/40 bg-amber-500/12 text-amber-700 dark:text-amber-300"
  end

  defp format_timestamp(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  defp format_timestamp(_value), do: "-"

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
