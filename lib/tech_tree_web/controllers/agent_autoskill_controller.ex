defmodule TechTreeWeb.AgentAutoskillController do
  use TechTreeWeb, :controller

  alias TechTree.Autoskill
  alias TechTreeWeb.{ApiError, ControllerHelpers}

  def create_skill(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_skill_version(agent, params) do
      {:ok, %{node: node}} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{node_id: node.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_skill_invalid",
          details: ApiError.translate_changeset(cs)
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_skill_create_failed",
          message: inspect(reason)
        })
    end
  end

  def create_eval(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_eval_version(agent, params) do
      {:ok, %{node: node}} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{node_id: node.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_eval_invalid",
          details: ApiError.translate_changeset(cs)
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_eval_create_failed",
          message: inspect(reason)
        })
    end
  end

  def create_result(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.publish_result(agent, params) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{result_id: result.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_result_invalid",
          details: ApiError.translate_changeset(cs)
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_result_create_failed",
          message: inspect(reason)
        })
    end
  end

  def create_community_review(conn, params) do
    create_review(conn, Map.put(params, "kind", "community"))
  end

  def create_replicable_review(conn, params) do
    create_review(conn, Map.put(params, "kind", "replicable"))
  end

  def create_listing(conn, %{"id" => skill_node_id} = params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_listing(agent, skill_node_id, params) do
      {:ok, listing} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{listing_id: listing.id, status: listing.status}})

      {:error, :replicable_review_threshold_not_met} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_listing_threshold_not_met"
        })

      {:error, %Ecto.Changeset{} = cs} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_listing_invalid",
          details: ApiError.translate_changeset(cs)
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_listing_create_failed",
          message: inspect(reason)
        })
    end
  end

  defp create_review(conn, params) do
    agent = ControllerHelpers.ensure_current_agent(conn)

    case Autoskill.create_review(agent, params) do
      {:ok, review} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{review_id: review.id}})

      {:error, %Ecto.Changeset{} = cs} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_review_invalid",
          details: ApiError.translate_changeset(cs)
        })

      {:error, reason} ->
        ApiError.render_halted(conn, :unprocessable_entity, %{
          code: "autoskill_review_create_failed",
          message: inspect(reason)
        })
    end
  end
end
