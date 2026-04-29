defmodule TechTreeWeb.AgentBbhDraftController do
  use TechTreeWeb, :controller

  alias TechTree.BBH
  alias TechTreeWeb.AgentApiResult

  def create(conn, params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.create_draft(claims, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :wallet_address_required} ->
        invalid(conn, "bbh_draft_invalid", "Agent wallet address is required")

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid_with_changeset(conn, "bbh_draft_invalid", "BBH draft is invalid", changeset)

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_draft_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_draft_failed", "BBH draft failed")
    end
  end

  def index(conn, _params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.list_drafts(claims) do
      {:ok, drafts} ->
        json(conn, %{data: drafts})

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_draft_list_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_draft_list_failed", "BBH draft list failed")
    end
  end

  def show(conn, %{"id" => capsule_id}) do
    case BBH.get_draft(capsule_id) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :capsule_not_found} ->
        not_found(conn, "bbh_capsule_not_found", "BBH draft not found")

      {:error, _reason} ->
        invalid(conn, "bbh_draft_failed", "BBH draft failed")
    end
  end

  def create_proposal(conn, %{"id" => capsule_id} = params) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.create_draft_proposal(claims, capsule_id, params) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :capsule_not_found} ->
        not_found(conn, "bbh_capsule_not_found", "BBH draft not found")

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid_with_changeset(
          conn,
          "bbh_draft_proposal_invalid",
          "Draft proposal is invalid",
          changeset
        )

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_draft_proposal_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_draft_proposal_failed", "BBH draft proposal failed")
    end
  end

  def proposals(conn, %{"id" => capsule_id}) do
    json(conn, %{data: BBH.list_draft_proposals(capsule_id)})
  end

  def apply_proposal(conn, %{"id" => capsule_id, "proposal_id" => proposal_id}) do
    case BBH.apply_draft_proposal(capsule_id, proposal_id) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :capsule_not_found} ->
        not_found(conn, "bbh_capsule_not_found", "BBH draft not found")

      {:error, :proposal_not_found} ->
        not_found(conn, "bbh_draft_proposal_not_found", "BBH draft proposal not found")

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid_with_changeset(
          conn,
          "bbh_draft_proposal_invalid",
          "Draft proposal is invalid",
          changeset
        )

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_draft_proposal_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_draft_proposal_failed", "BBH draft proposal failed")
    end
  end

  def ready(conn, %{"id" => capsule_id}) do
    claims = conn.assigns[:current_agent_claims] || %{}

    case BBH.ready_draft(claims, capsule_id) do
      {:ok, payload} ->
        json(conn, %{data: payload})

      {:error, :capsule_not_found} ->
        not_found(conn, "bbh_capsule_not_found", "BBH draft not found")

      {:error, :draft_not_owned} ->
        AgentApiResult.render_message(
          conn,
          :forbidden,
          "bbh_draft_not_owned",
          "Only the draft owner can mark a draft ready"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid_with_changeset(conn, "bbh_draft_invalid", "BBH draft is invalid", changeset)

      {:error, %ArgumentError{} = error} ->
        invalid(conn, "bbh_draft_invalid", Exception.message(error))

      {:error, _reason} ->
        invalid(conn, "bbh_draft_failed", "BBH draft failed")
    end
  end

  defp not_found(conn, code, message) do
    AgentApiResult.render_message(conn, :not_found, code, message)
  end

  defp invalid(conn, code, message) do
    AgentApiResult.render_message(conn, :unprocessable_entity, code, message)
  end

  defp invalid_with_changeset(conn, code, message, changeset) do
    AgentApiResult.render_changeset_errors(conn, :unprocessable_entity, code, message, changeset)
  end
end
