defmodule TechTreeWeb.AgentApiResult do
  @moduledoc false

  alias TechTreeWeb.ApiError

  def render_changeset(conn, status, code, %Ecto.Changeset{} = changeset) do
    ApiError.render_halted(conn, status, %{
      code: code,
      details: ApiError.translate_changeset(changeset)
    })
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
end
