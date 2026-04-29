defmodule TechTreeWeb.Platform.ModerationLive do
  @moduledoc false
  use TechTreeWeb, :live_view

  import TechTreeWeb.PlatformComponents

  alias TechTree.Accounts
  alias TechTree.Accounts.HumanUser
  alias TechTree.Moderation
  alias TechTreeWeb.Platform.ModerationComponents

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
  def handle_event("moderation-action", %{"action" => action, "id" => id} = params, socket) do
    handle_moderation_action(socket, action, id, params["selected"])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.platform_shell
        route_key={@route_key}
        title="Moderation"
        kicker="Trust And Safety"
        subtitle="One operator surface for live chatbox review, actor history, and the recent moderation audit trail."
        client_config={@client_config}
      >
        <section id="platform-moderation-scene" class="grid gap-4 xl:grid-cols-[1.15fr_0.85fr]">
          <ModerationComponents.queue_panel
            filters={@filters}
            reason={@reason}
            messages={@messages}
            selected_message={@selected_message}
          />

          <div class="grid gap-4">
            <ModerationComponents.history_panel
              selected_message={@selected_message}
              actor_history={@actor_history}
            />
            <ModerationComponents.actions_panel recent_actions={@recent_actions} />
          </div>
        </section>
      </.platform_shell>
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp refresh_dashboard(socket) do
    dashboard =
      Moderation.chatbox_dashboard(socket.assigns.filters, socket.assigns.selected_message_id)

    socket
    |> assign(:messages, dashboard.messages)
    |> assign(:selected_message_id, dashboard.selected_message_id)
    |> assign(:selected_message, dashboard.selected_message)
    |> assign(:actor_history, dashboard.actor_history)
    |> assign(:recent_actions, dashboard.recent_actions)
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

  defp handle_moderation_action(socket, raw_action, raw_id, raw_selected_id) do
    with {:ok, action} <- parse_action(raw_action),
         {:ok, target_id} <- parse_required_id(raw_id),
         {:ok, _status} <-
           Moderation.apply_action(
             action,
             target_id,
             socket.assigns.current_admin,
             socket.assigns.reason
           ) do
      selected_message_id = parse_id(raw_selected_id) || socket.assigns.selected_message_id

      refreshed_socket =
        socket
        |> assign(:selected_message_id, selected_message_id)
        |> refresh_dashboard()

      {:noreply,
       refreshed_socket
       |> put_flash(:info, action_flash(action))
       |> assign(:selected_message_id, refreshed_socket.assigns.selected_message_id)}
    else
      :error ->
        {:noreply, put_flash(socket, :error, "Invalid target id")}

      {:error, :invalid_action} ->
        {:noreply, put_flash(socket, :error, "Invalid moderation action")}

      {:error, reason}
      when reason in [:message_not_found, :human_not_found, :agent_not_found] ->
        handle_missing_target(socket)
    end
  end

  defp parse_action("hide_chatbox_message"), do: {:ok, :hide_chatbox_message}
  defp parse_action("unhide_chatbox_message"), do: {:ok, :unhide_chatbox_message}
  defp parse_action("ban_human"), do: {:ok, :ban_human}
  defp parse_action("unban_human"), do: {:ok, :unban_human}
  defp parse_action("ban_agent"), do: {:ok, :ban_agent}
  defp parse_action("unban_agent"), do: {:ok, :unban_agent}
  defp parse_action(_action), do: {:error, :invalid_action}

  defp action_flash(:hide_chatbox_message), do: "Message hidden"
  defp action_flash(:unhide_chatbox_message), do: "Message restored"
  defp action_flash(:ban_human), do: "Human banned"
  defp action_flash(:unban_human), do: "Human restored"
  defp action_flash(:ban_agent), do: "Agent banned"
  defp action_flash(:unban_agent), do: "Agent restored"

  defp handle_missing_target(socket) do
    {:noreply,
     socket
     |> refresh_dashboard()
     |> put_flash(:error, "That item is no longer available.")}
  end
end
