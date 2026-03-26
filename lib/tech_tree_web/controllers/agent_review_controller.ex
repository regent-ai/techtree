defmodule TechTreeWeb.AgentReviewController do
  use TechTreeWeb, :controller

  alias TechTree.BBH
  alias TechTreeWeb.ApiError

  def open(conn, params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.list_reviews(claims, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :reviewer_not_approved} ->
        reviewer_not_approved(conn)

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_review_invalid", Exception.message(error))

      {:error, reason} ->
        invalid(conn, "bbh_review_failed", inspect(reason))
    end
  end

  def claim(conn, %{"request_id" => request_id}) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.claim_review(claims, request_id) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :reviewer_not_approved} ->
        reviewer_not_approved(conn)

      {:error, :review_request_not_found} ->
        not_found(conn, "bbh_review_request_not_found", "Review request not found")

      {:error, :review_request_not_claimable} ->
        invalid(conn, "bbh_review_request_not_claimable", "Review request is not claimable")

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid_with_changeset(conn, "bbh_review_invalid", "Review request is invalid", changeset)

      {:error, reason} ->
        invalid(conn, "bbh_review_failed", inspect(reason))
    end
  end

  def packet(conn, %{"request_id" => request_id}) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.get_review_packet(claims, request_id) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :reviewer_not_approved} ->
        reviewer_not_approved(conn)

      {:error, :review_request_not_found} ->
        not_found(conn, "bbh_review_request_not_found", "Review request not found")

      {:error, :review_request_not_claimed} ->
        ApiError.render_halted(conn, :forbidden, %{
          code: "bbh_review_request_not_claimed",
          message: "Review request must be claimed before pulling the packet"
        })

      {:error, reason} ->
        invalid(conn, "bbh_review_failed", inspect(reason))
    end
  end

  def submit(conn, %{"request_id" => request_id} = params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    body_request_id = Map.get(conn.body_params || %{}, "request_id")

    if body_request_id && body_request_id != request_id do
      invalid(conn, "bbh_review_request_mismatch", "request_id in the body must match the URL")
    else
      case BBH.submit_review(claims, request_id, params) do
        {:ok, payload} ->
          json(conn, %{data: payload})

        {:error, :reviewer_not_approved} ->
          reviewer_not_approved(conn)

        {:error, :review_request_not_found} ->
          not_found(conn, "bbh_review_request_not_found", "Review request not found")

        {:error, :review_request_not_claimed} ->
          ApiError.render_halted(conn, :forbidden, %{
            code: "bbh_review_request_not_claimed",
            message: "Only the claiming reviewer can submit this review"
          })

        {:error, :review_request_mismatch} ->
          invalid(
            conn,
            "bbh_review_request_mismatch",
            "request_id in the body must match the URL"
          )

        {:error, %Ecto.Changeset{} = changeset} ->
          invalid_with_changeset(
            conn,
            "bbh_review_invalid",
            "Review submission is invalid",
            changeset
          )

        {:error, %ArgumentError{} = error} ->
          invalid(conn, "bbh_review_invalid", Exception.message(error))

        {:error, reason} ->
          invalid(conn, "bbh_review_failed", inspect(reason))
      end
    end
  end

  defp reviewer_not_approved(conn) do
    ApiError.render_halted(conn, :forbidden, %{
      code: "bbh_reviewer_not_approved",
      message: "Approved reviewer status is required"
    })
  end

  defp not_found(conn, code, message) do
    ApiError.render_halted(conn, :not_found, %{code: code, message: message})
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
