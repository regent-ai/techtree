defmodule TechTreeWeb.HomeRegentScene do
  @moduledoc false

  alias TechTreeWeb.HomePresenter

  def build(assigns) do
    %{
      "app" => "techtree",
      "theme" => "techtree",
      "activeFace" => active_face(assigns),
      "sceneVersion" => Map.get(assigns, :regent_scene_version, 0),
      "camera" => %{
        "type" => "oblique",
        "angle" => 315,
        "distance" => 28
      },
      "faces" => [graph_face(assigns), grid_face(assigns)],
      "meta" => %{
        "selectedNodeId" => maybe_string_id(assigns.selected_node_id),
        "selectedAgentId" => maybe_string_id(assigns.selected_agent_id),
        "gridDepth" => assigns.grid_view_depth || 0
      }
    }
  end

  defp active_face(assigns) do
    case Map.get(assigns, :view_mode) do
      "grid" -> "grid"
      _ -> "graph"
    end
  end

  defp graph_face(assigns) do
    nodes = visible_graph_nodes(assigns)
    node_ids = MapSet.new(Enum.map(nodes, & &1.id))
    subtree_ids = subtree_ids(assigns)
    selected_id = assigns.selected_node_id

    %{
      "id" => "graph",
      "title" => "Dependency observatory",
      "sigil" => "seed",
      "orientation" => "front",
      "landmarkNodeId" => maybe_string_id(selected_id),
      "meta" => %{
        "mode" => "graph",
        "nodeCount" => length(nodes)
      },
      "nodes" =>
        nodes
        |> Enum.with_index()
        |> Enum.map(fn {node, index} ->
          %{
            "id" => Integer.to_string(node.id),
            "kind" => node_kind(node),
            "geometry" => node_geometry(node),
            "sigil" => node_sigil(node),
            "label" => HomePresenter.display_node_title(node, assigns.seed_catalog),
            "status" => node_status(node, assigns, subtree_ids),
            "position" => graph_position(node, index),
            "size" => graph_size(node, selected_id),
            "opaque" => true,
            "meta" => %{
              "node_id" => node.id,
              "face_action" => "select-node",
              "seed" => node.seed,
              "kind" => node.kind,
              "result_status" => node.result_status
            }
          }
        end),
      "conduits" =>
        assigns.graph_edges
        |> Enum.filter(fn edge ->
          MapSet.member?(node_ids, edge.source_id) and MapSet.member?(node_ids, edge.target_id)
        end)
        |> Enum.map(fn edge ->
          %{
            "id" => edge.id,
            "from" => Integer.to_string(edge.source_id),
            "to" => Integer.to_string(edge.target_id),
            "kind" => "dependency",
            "state" => graph_conduit_state(edge, assigns, subtree_ids),
            "shape" => "rounded",
            "radius" => 0.6
          }
        end)
    }
  end

  defp grid_face(assigns) do
    grid_nodes =
      assigns.grid_view_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, index} ->
        {x, y, z} = grid_position(index)

        %{
          "id" => Integer.to_string(node.id),
          "kind" => node_kind(node),
          "geometry" => "cube",
          "sigil" => node_sigil(node),
          "label" => HomePresenter.display_node_title(node, assigns.seed_catalog),
          "status" => grid_node_status(node, assigns),
          "position" => [x, y, z],
          "size" => [2, 2, 2],
          "opaque" => true,
          "meta" => %{
            "node_id" => node.id,
            "face_action" => "open-grid-node",
            "seed" => node.seed,
            "kind" => node.kind
          }
        }
      end)

    nodes =
      if assigns.grid_view_depth > 0 do
        [
          %{
            "id" => "grid:return",
            "kind" => "portal",
            "geometry" => "carved_cube",
            "sigil" => "gate",
            "label" => "Return one level",
            "status" => "active",
            "position" => [-8, -5, 0],
            "size" => [2, 2, 2],
            "opaque" => true,
            "meta" => %{
              "face_action" => "return-grid-level"
            }
          }
          | grid_nodes
        ]
      else
        grid_nodes
      end

    %{
      "id" => "grid",
      "title" => "Cube field",
      "sigil" => "gate",
      "orientation" => "right",
      "landmarkNodeId" => maybe_string_id(assigns.selected_node_id),
      "meta" => %{
        "mode" => "grid",
        "depth" => assigns.grid_view_depth,
        "key" => assigns.grid_view_key
      },
      "nodes" => nodes,
      "conduits" => []
    }
  end

  defp visible_graph_nodes(assigns) do
    nodes = Map.get(assigns, :graph_nodes, [])

    if assigns.filter_to_null_results? do
      null_ids =
        nodes
        |> Enum.filter(&(&1.result_status == "null"))
        |> Enum.map(& &1.id)
        |> MapSet.new()

      context_ids =
        null_ids
        |> Enum.reduce(null_ids, fn node_id, acc ->
          ancestor_ids(node_id, assigns.graph_node_index)
          |> Enum.reduce(acc, &MapSet.put(&2, &1))
        end)
        |> maybe_put(assigns.selected_node_id)
        |> maybe_put(assigns.subtree_root_id)

      Enum.filter(nodes, &MapSet.member?(context_ids, &1.id))
    else
      nodes
    end
  end

  defp ancestor_ids(node_id, graph_node_index) do
    node_id
    |> Stream.unfold(fn current_id ->
      case Map.get(graph_node_index, current_id) do
        %{parent_id: parent_id} when is_integer(parent_id) -> {parent_id, parent_id}
        _ -> nil
      end
    end)
    |> Enum.to_list()
  end

  defp subtree_ids(%{subtree_root_id: nil}), do: MapSet.new()
  defp subtree_ids(%{subtree_mode: nil}), do: MapSet.new()

  defp subtree_ids(assigns) do
    root_id = assigns.subtree_root_id
    children_by_parent = assigns.graph_children_by_parent

    descendants =
      case assigns.subtree_mode do
        "children" ->
          Map.get(children_by_parent, root_id, [])
          |> Enum.map(& &1.id)

        "descendants" ->
          collect_descendants(root_id, children_by_parent)

        _ ->
          []
      end

    descendants
    |> Enum.reduce(MapSet.new([root_id]), &MapSet.put(&2, &1))
  end

  defp collect_descendants(root_id, children_by_parent) do
    children_by_parent
    |> Map.get(root_id, [])
    |> Enum.flat_map(fn child ->
      [child.id | collect_descendants(child.id, children_by_parent)]
    end)
  end

  defp graph_position(node, index) do
    x = round((node.x || 0.0) * 20)
    y = (node.depth || 0) * 6
    z = max(0, round((1.0 - (node.y || 0.0)) * 4) + rem(index, 3))
    [x, y, z]
  end

  defp graph_size(node, selected_id) do
    cond do
      node.id == selected_id -> [3, 3, 2]
      (node.depth || 0) == 0 -> [3, 3, 2]
      true -> [2, 2, 2]
    end
  end

  defp grid_position(index) do
    row = div(index, 4)
    column = rem(index, 4)
    row_offset = if rem(row, 2) == 1, do: 2, else: 0
    x = column * 5 + row_offset - 8
    y = row * 5
    z = rem(index, 2) * 2
    {x, y, z}
  end

  defp grid_node_status(node, assigns) do
    cond do
      assigns.grid_modal_node && assigns.grid_modal_node.id == node.id -> "focused"
      assigns.selected_node_id == node.id -> "active"
      node.result_status == "null" -> "invalid"
      true -> "available"
    end
  end

  defp graph_conduit_state(edge, assigns, subtree_ids) do
    selected_id = assigns.selected_node_id

    cond do
      edge.source_id == selected_id or edge.target_id == selected_id ->
        "flowing"

      MapSet.member?(subtree_ids, edge.source_id) and MapSet.member?(subtree_ids, edge.target_id) ->
        "flowing"

      assigns.selected_agent_id &&
          Enum.any?([edge.source_id, edge.target_id], fn node_id ->
            case Map.get(assigns.graph_node_index, node_id) do
              %{agent_id: agent_id} -> agent_id == assigns.selected_agent_id
              _ -> false
            end
          end) ->
        "flowing"

      true ->
        "visible"
    end
  end

  defp node_status(node, assigns, subtree_ids) do
    cond do
      node.id == assigns.selected_node_id ->
        "focused"

      assigns.filter_to_null_results? and node.result_status != "null" ->
        "ghosted"

      assigns.show_null_results? and node.result_status == "null" ->
        "invalid"

      MapSet.member?(subtree_ids, node.id) and node.id != assigns.subtree_root_id ->
        "active"

      assigns.selected_agent_id && node.agent_id == assigns.selected_agent_id ->
        "active"

      node.kind == "result" and node.result_status == "success" ->
        "complete"

      node.kind == "null_result" ->
        "invalid"

      true ->
        "available"
    end
  end

  defp node_kind(%{kind: kind}) when kind in ["seed", "hypothesis"], do: "portal"
  defp node_kind(%{kind: kind}) when kind in ["result", "review"], do: "proof"
  defp node_kind(%{kind: kind}) when kind in ["skill", "synthesis"], do: "action"
  defp node_kind(%{kind: "null_result"}), do: "state"
  defp node_kind(%{kind: "meta"}), do: "memory"
  defp node_kind(_node), do: "state"

  defp node_geometry(%{kind: "null_result"}), do: "socket"
  defp node_geometry(%{kind: "review"}), do: "carved_cube"
  defp node_geometry(_node), do: "cube"

  defp node_sigil(%{kind: kind}) when kind in ["seed", "hypothesis"], do: "seed"
  defp node_sigil(%{kind: kind}) when kind in ["review", "null_result"], do: "eye"
  defp node_sigil(%{kind: "result"}), do: "seal"
  defp node_sigil(%{kind: "skill"}), do: "gate"
  defp node_sigil(%{kind: "synthesis"}), do: "seal"
  defp node_sigil(_node), do: "gate"

  defp maybe_string_id(nil), do: nil
  defp maybe_string_id(value), do: to_string(value)

  defp maybe_put(set, nil), do: set
  defp maybe_put(set, value), do: MapSet.put(set, value)
end
