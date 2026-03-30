defmodule TechTree.Nodes.Publishing.Attrs do
  @moduledoc false

  alias TechTree.Nodes.Reads

  def normalize_create_attrs(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("parent_id", nil, &normalize_optional_id/1)
    |> Map.update("paid_payload", nil, &normalize_paid_payload/1)
    |> normalize_publish_idempotency_key_attr()
  end

  def normalize_publish_idempotency_key_attr(attrs) do
    key =
      attrs
      |> Map.get("idempotency_key", Map.get(attrs, "publish_idempotency_key"))
      |> normalize_optional_text()

    case key do
      nil -> Map.delete(attrs, "publish_idempotency_key")
      normalized -> Map.put(attrs, "publish_idempotency_key", normalized)
    end
  end

  def normalize_optional_id(nil), do: nil
  def normalize_optional_id(value), do: Reads.normalize_id(value)

  def normalize_paid_payload(value) when is_map(value) do
    Map.new(value, fn {key, payload_value} -> {to_string(key), payload_value} end)
  end

  def normalize_paid_payload(_value), do: nil

  def normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_optional_text(nil), do: nil
  def normalize_optional_text(value), do: value

  def build_bundle_payload(normalized_attrs) do
    %{
      "notebook_source" => normalized_attrs["notebook_source"],
      "skill_md_body" => normalized_attrs["skill_md_body"]
    }
  end

  def attr_value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
end
