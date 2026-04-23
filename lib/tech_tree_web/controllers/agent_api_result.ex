defmodule TechTreeWeb.AgentApiResult do
  @moduledoc false

  alias TechTreeWeb.ApiError

  def render_changeset(conn, status, code, %Ecto.Changeset{} = changeset) do
    ApiError.render_halted(conn, status, %{
      code: code,
      details: ApiError.translate_changeset(changeset)
    })
  end

  def render_changeset_errors(conn, status, code, message, %Ecto.Changeset{} = changeset) do
    render_message(conn, status, code, message, %{
      errors: translate_changeset_errors(changeset)
    })
  end

  def render_message(conn, status, code, message, details \\ nil) do
    payload =
      %{code: code, message: message}
      |> maybe_put_details(details)

    ApiError.render_halted(conn, status, payload)
  end

  def render_reason(conn, status, code, reason, overrides \\ %{}) do
    payload = %{code: code}

    payload =
      case public_reason(reason, overrides) do
        nil -> payload
        message -> Map.put(payload, :message, message)
      end

    ApiError.render_halted(conn, status, payload)
  end

  def public_reason(reason, overrides \\ %{})

  def public_reason(reason, overrides) when is_atom(reason) do
    Map.get(overrides, reason, Atom.to_string(reason))
  end

  def public_reason({:error, reason}, overrides) do
    public_reason(reason, overrides)
  end

  def public_reason(_reason, _overrides), do: "unexpected_error"

  defp maybe_put_details(payload, nil), do: payload
  defp maybe_put_details(payload, details), do: Map.put(payload, :details, details)

  defp translate_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
