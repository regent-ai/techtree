defmodule TechTreeWeb.AdminReviewerController do
  use TechTreeWeb, :controller

  alias TechTree.BBH
  alias TechTreeWeb.ApiError

  def approve(conn, %{"wallet" => wallet}) do
    update(conn, wallet, "approved")
  end

  def reject(conn, %{"wallet" => wallet}) do
    update(conn, wallet, "rejected")
  end

  defp update(conn, wallet, status) do
    admin_ref =
      conn.assigns[:current_human] &&
        (conn.assigns.current_human.wallet_address || "human:#{conn.assigns.current_human.id}")

    case BBH.approve_reviewer(wallet, admin_ref, status) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid_with_changeset(
          conn,
          "bbh_reviewer_invalid",
          "Reviewer profile is invalid",
          changeset
        )

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_reviewer_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_reviewer_failed", "BBH reviewer update failed")
    end
  end

  defp invalid(conn, code, message) do
    ApiError.render_halted(conn, :unprocessable_entity, %{"code" => code, "message" => message})
  end

  defp invalid_with_changeset(conn, code, message, changeset) do
    ApiError.render_halted(conn, :unprocessable_entity, %{
      "code" => code,
      "message" => message,
      "details" => %{errors: translate_errors(changeset)}
    })
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
