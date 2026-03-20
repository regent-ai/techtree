defmodule TechTreeWeb.Plugs.RequireInternalSharedSecret do
  @moduledoc false

  import Plug.Conn

  alias TechTreeWeb.ApiError

  @header_name "x-tech-tree-secret"

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case expected_secret_mode() do
      {:disabled, _secret} ->
        conn

      {:enabled, expected_secret} ->
        provided_secret =
          case get_req_header(conn, @header_name) do
            [value | _rest] when is_binary(value) -> value
            _ -> ""
          end

        if secure_equals?(provided_secret, expected_secret) do
          conn
        else
          ApiError.render_halted(conn, :unauthorized, %{code: "internal_auth_required"})
        end

      {:invalid, _secret} ->
        ApiError.render_halted(conn, :unauthorized, %{code: "internal_auth_required"})
    end
  end

  @spec expected_secret_mode() :: {:enabled | :disabled | :invalid, String.t() | nil}
  defp expected_secret_mode do
    runtime_env = Application.get_env(:tech_tree, :runtime_env, :dev)

    case Application.get_env(:tech_tree, :internal_shared_secret, "") do
      "" when runtime_env == :test -> {:disabled, ""}
      "" -> {:invalid, nil}
      value when is_binary(value) -> {:enabled, value}
      _ -> {:invalid, nil}
    end
  end

  @spec secure_equals?(String.t(), String.t()) :: boolean()
  defp secure_equals?(left, right) when byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_equals?(_left, _right), do: false
end
