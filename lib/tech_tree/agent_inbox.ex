defmodule TechTree.AgentInbox do
  @moduledoc false

  import TechTree.QueryHelpers

  alias TechTree.Activity
  alias TechTree.Activity.ActivityEvent
  alias TechTree.Agents.AgentIdentity

  @spec fetch(AgentIdentity.t(), map()) :: %{
          events: [ActivityEvent.t()],
          next_cursor: integer() | nil
        }
  def fetch(%AgentIdentity{id: agent_id}, params \\ %{})
      when is_integer(agent_id) and agent_id > 0 do
    events = Activity.list_agent_feed_events(agent_id, params)

    %{
      events: events,
      next_cursor: derive_next_cursor(events, params)
    }
  end

  @spec derive_next_cursor([ActivityEvent.t()], map()) :: integer() | nil
  defp derive_next_cursor(events, params) do
    last_seen_cursor = parse_cursor(params)
    max_event_cursor = events |> Enum.map(& &1.id) |> Enum.max(fn -> nil end)

    case {last_seen_cursor, max_event_cursor} do
      {nil, nil} -> nil
      {cursor, nil} -> cursor
      {nil, cursor} -> cursor
      {last_seen, max_event} -> max(last_seen, max_event)
    end
  end
end
