defmodule TechTreeWeb.AgentReviewerController do
  use TechTreeWeb, :controller

  alias TechTree.BBH
  alias TechTreeWeb.ApiError

  def start_orcid_link(conn, _params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.start_reviewer_orcid_link(claims) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid_with_changeset(
          conn,
          "bbh_orcid_link_invalid",
          "ORCID link request is invalid",
          changeset
        )

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_orcid_link_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_orcid_link_failed", "BBH ORCID link failed")
    end
  end

  def orcid_link_status(conn, %{"request_id" => request_id}) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.get_reviewer_orcid_link_status(claims, request_id) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :orcid_request_not_found} ->
        ApiError.render_halted(conn, :not_found, %{
          code: "bbh_orcid_request_not_found",
          message: "ORCID link request not found"
        })

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_orcid_link_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_orcid_link_failed", "BBH ORCID link failed")
    end
  end

  def apply(conn, params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.apply_reviewer(claims, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :reviewer_orcid_required} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "bbh_reviewer_orcid_required",
          message: "An authenticated ORCID link is required before reviewer application"
        })

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
        invalid(conn, "bbh_reviewer_failed", "BBH reviewer request failed")
    end
  end

  def me(conn, _params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.get_reviewer(claims) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_reviewer_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_reviewer_failed", "BBH reviewer request failed")
    end
  end

  defp invalid(conn, code, message) do
    ApiError.render_halted(conn, :unprocessable_entity, %{code: code, message: message})
  end

  defp invalid_with_changeset(conn, code, message, changeset) do
    ApiError.render_halted(conn, :unprocessable_entity, %{
      code: code,
      message: message,
      details: %{errors: translate_errors(changeset)}
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
