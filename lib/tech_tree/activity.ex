defmodule TechTree.Activity do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Repo
  alias TechTree.Activity.ActivityEvent

  @spec list_public_events(map()) :: [ActivityEvent.t()]
  def list_public_events(params) do
    limit = parse_limit(params, 50)

    ActivityEvent
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec log!(String.t(), String.t() | atom(), integer() | nil, integer() | nil, map()) :: ActivityEvent.t()
  def log!(event_type, actor_type, actor_ref, subject_node_id, payload \\ %{}) do
    %ActivityEvent{}
    |> ActivityEvent.changeset(%{
      event_type: event_type,
      actor_type: actor_type,
      actor_ref: actor_ref,
      subject_node_id: subject_node_id,
      payload: payload
    })
    |> Repo.insert!()
  end

  @spec parse_limit(map(), pos_integer()) :: pos_integer()
  defp parse_limit(params, fallback) do
    case Map.get(params, "limit") do
      nil -> fallback
      value when is_integer(value) and value > 0 -> min(value, 200)
      value when is_binary(value) ->
        value
        |> String.to_integer()
        |> min(200)

      _ -> fallback
    end
  rescue
    _ -> fallback
  end
end
