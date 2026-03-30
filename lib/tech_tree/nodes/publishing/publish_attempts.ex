defmodule TechTree.Nodes.Publishing.PublishAttempts do
  @moduledoc false

  def normalize_publish_attempt_update_fields(extra_fields, status) do
    inc_fields =
      case status do
        "submitted" -> [attempt_count: 1]
        "failed_anchor" -> [attempt_count: 1]
        _ -> []
      end

    set_fields =
      extra_fields
      |> Map.update(:last_error, default_last_error(status), &normalize_last_error(status, &1))
      |> Enum.to_list()

    {set_fields, inc_fields}
  end

  def default_last_error("failed_anchor"), do: nil
  def default_last_error(_status), do: nil

  def normalize_last_error("failed_anchor", value), do: inspect(value)
  def normalize_last_error(_status, value), do: value
end
