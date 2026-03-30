defmodule TechTree.Autoskill.Projection do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Autoskill.{Listing, NodeBundle, Result, Review}
  alias TechTree.Autoskill.Listings
  alias TechTree.Nodes.Node
  alias TechTree.Repo

  def attach_projection([]), do: []

  def attach_projection(%Node{} = node) do
    case attach_projection([node]) do
      [projected] -> projected
      _ -> node
    end
  end

  def attach_projection(nodes) when is_list(nodes) do
    node_ids =
      nodes
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)

    bundles_by_node_id =
      NodeBundle
      |> where([bundle], bundle.node_id in ^node_ids)
      |> Repo.all()
      |> Map.new(&{&1.node_id, &1})

    scorecards_by_skill_id =
      nodes
      |> Enum.filter(&(&1.kind == :skill and Map.has_key?(bundles_by_node_id, &1.id)))
      |> Enum.map(& &1.id)
      |> scorecards_for_skill_ids()
      |> Map.new(fn scorecard ->
        {scorecard.skill_node_id, Map.delete(scorecard, :skill_node_id)}
      end)

    listings_by_skill_id =
      Listing
      |> where([listing], listing.skill_node_id in ^node_ids)
      |> Repo.all()
      |> Map.new(fn listing -> {listing.skill_node_id, Listings.encode_listing(listing)} end)

    Enum.map(nodes, fn node ->
      autoskill =
        case Map.get(bundles_by_node_id, node.id) do
          nil ->
            nil

          bundle ->
            build_projection(
              node,
              bundle,
              scorecards_by_skill_id[node.id],
              listings_by_skill_id[node.id]
            )
        end

      %{node | autoskill: autoskill}
    end)
  end

  def scorecards_for_skill_ids([]), do: []

  def scorecards_for_skill_ids(skill_ids) do
    community =
      Review
      |> where([review], review.skill_node_id in ^skill_ids and review.kind == :community)
      |> group_by([review], review.skill_node_id)
      |> select([review], %{
        skill_node_id: review.skill_node_id,
        count: count(review.id),
        avg_rating: avg(review.rating)
      })
      |> Repo.all()
      |> Map.new(&{&1.skill_node_id, &1})

    replicable =
      Review
      |> join(:inner, [review], result in Result, on: result.id == review.result_id)
      |> where(
        [review, _result],
        review.skill_node_id in ^skill_ids and review.kind == :replicable
      )
      |> group_by([review, _result], review.skill_node_id)
      |> select([review, result], %{
        skill_node_id: review.skill_node_id,
        review_count: count(review.id),
        unique_agent_count: count(fragment("distinct ?", review.reviewer_agent_id)),
        median_score:
          fragment("percentile_cont(0.5) within group (order by ?)", result.normalized_score)
      })
      |> Repo.all()
      |> Map.new(&{&1.skill_node_id, &1})

    Enum.map(skill_ids, fn skill_id ->
      %{
        skill_node_id: skill_id,
        community: %{
          count: (community[skill_id] && community[skill_id].count) || 0,
          avg_rating: community[skill_id] && community[skill_id].avg_rating
        },
        replicable: %{
          review_count: (replicable[skill_id] && replicable[skill_id].review_count) || 0,
          unique_agent_count:
            (replicable[skill_id] && replicable[skill_id].unique_agent_count) || 0,
          median_score: replicable[skill_id] && replicable[skill_id].median_score
        }
      }
    end)
  end

  def build_projection(node, bundle, scorecard, listing) do
    %{
      flavor: Atom.to_string(bundle.bundle_type),
      access_mode: Atom.to_string(bundle.access_mode),
      preview_md: bundle.preview_md,
      marimo_entrypoint: bundle.marimo_entrypoint,
      primary_file: bundle.primary_file,
      bundle_hash: bundle.bundle_hash,
      scorecard: scorecard,
      listing: if(node.kind == :skill, do: listing, else: nil)
    }
  end
end
