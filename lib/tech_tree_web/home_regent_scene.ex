defmodule TechTreeWeb.HomeRegentScene do
  @moduledoc false

  alias Regent.SceneSpec
  alias TechTreeWeb.HomePresenter

  def build(assigns) do
    focus_target_id = focus_target_id(assigns)

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
      "cameraPresets" => %{
        "overview" => %{
          "type" => "oblique",
          "angle" => 315,
          "distance" => 28,
          "padding" => 42,
          "zoom" => 1.0
        },
        "focus_travel" => %{
          "type" => "oblique",
          "angle" => 304,
          "distance" => 21,
          "padding" => 24,
          "zoom" => 2.35
        },
        "node_focus" => %{
          "type" => "oblique",
          "angle" => 300,
          "distance" => 18,
          "padding" => 20,
          "zoom" => 3.1
        },
        "grid_focus" => %{
          "type" => "oblique",
          "angle" => 315,
          "distance" => 22,
          "padding" => 28,
          "zoom" => 2.0
        }
      },
      "activeCameraPreset" => active_camera_preset(assigns, focus_target_id),
      "cameraTargetId" => focus_target_id,
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

  defp active_camera_preset(assigns, focus_target_id) do
    case active_face(assigns) do
      "grid" -> "grid_focus"
      _ -> if(is_binary(focus_target_id), do: "focus_travel", else: "overview")
    end
  end

  defp focus_target_id(assigns) do
    cond do
      assigns.grid_modal_node -> Integer.to_string(assigns.grid_modal_node.id)
      is_binary(assigns.node_focus_target_id) -> assigns.node_focus_target_id
      true -> nil
    end
  end

  defp graph_face(assigns) do
    nodes = visible_graph_nodes(assigns)
    node_ids = MapSet.new(Enum.map(nodes, & &1.id))
    subtree_ids = subtree_ids(assigns)
    selected_id = assigns.selected_node_id

    graph_nodes =
      nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, index} ->
        %{
          "id" => Integer.to_string(node.id),
          "kind" => node_kind(node),
          "geometry" => node_geometry(node),
          "sigil" => node_sigil(node),
          "label" => HomePresenter.display_node_title(node, assigns.seed_catalog),
          "actionLabel" => "Open node chamber",
          "intent" => "scene_action",
          "groupRole" => if((node.depth || 0) == 0, do: "landmark", else: "chamber-entry"),
          "historyKey" => "techtree:graph:overview",
          "status" => node_status(node, assigns, subtree_ids),
          "parentId" => node.parent_id,
          "position" => graph_position(node, index),
          "size" => graph_size(node, selected_id, overview_graph?(assigns)),
          "scale" => graph_scale(node, selected_id, overview_graph?(assigns)),
          "scaleOrigin" => [0.5, 1, 0.5],
          "opaque" => true,
          "meta" => %{
            "node_id" => node.id,
            "face_action" => "select-node",
            "seed" => node.seed,
            "kind" => node.kind,
            "result_status" => node.result_status
          }
        }
      end)

    graph_conduits =
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

    {commands, markers} = assemble_face(graph_nodes, graph_conduits)
    commands = graph_backbone_commands(graph_nodes) ++ commands

    SceneSpec.face(
      "graph",
      "Dependency observatory",
      "seed",
      commands,
      markers,
      orientation: "front",
      landmark_target_id: maybe_string_id(selected_id),
      meta: %{
        "mode" => "graph",
        "nodeCount" => length(nodes)
      }
    )
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
          "actionLabel" => "Inspect grid node",
          "intent" => "navigate",
          "groupRole" => "landmark",
          "historyKey" => "techtree:grid:overview",
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
            "actionLabel" => "Back one level",
            "intent" => "back",
            "groupRole" => "landmark",
            "historyKey" => "techtree:grid:return",
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

    {commands, markers} = assemble_face(nodes, [])

    SceneSpec.face(
      "grid",
      "Cube field",
      "gate",
      commands,
      markers,
      orientation: "right",
      landmark_target_id: maybe_string_id(assigns.selected_node_id),
      meta: %{
        "mode" => "grid",
        "depth" => assigns.grid_view_depth,
        "key" => assigns.grid_view_key
      }
    )
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

  defp graph_size(node, selected_id, overview?) do
    cond do
      node.id == selected_id -> [3, 3, 2]
      (node.depth || 0) == 0 -> [3, 3, 2]
      overview? and (node.depth || 0) == 1 -> [2, 2, 1]
      overview? -> [2, 1, 1]
      true -> [2, 2, 2]
    end
  end

  defp graph_scale(node, selected_id, overview?) do
    cond do
      node.id == selected_id -> [1.0, 1.0, 1.0]
      (node.depth || 0) == 0 and overview? -> [0.92, 0.84, 0.92]
      (node.depth || 0) == 0 -> [1.0, 1.0, 1.0]
      overview? and (node.depth || 0) == 1 -> [0.74, 0.64, 0.74]
      overview? -> [0.58, 0.48, 0.58]
      (node.depth || 0) == 1 -> [0.9, 0.84, 0.9]
      true -> [0.78, 0.72, 0.78]
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

  defp graph_backbone_commands(nodes) do
    nodes
    |> Enum.filter(&is_nil(Map.get(&1, "parentId")))
    |> Enum.with_index()
    |> Enum.map(fn {node, index} ->
      from = SceneSpec.anchor(Map.fetch!(node, "position"), Map.fetch!(node, "size"))
      to = [elem_or(from, 0) + 4 + index * 2, elem_or(from, 1) + 18, elem_or(from, 2) + 8]

      SceneSpec.add_line(
        "graph:backbone:#{node["id"]}",
        from,
        to,
        radius: 0.75,
        shape: "rounded",
        style: %{
          "default" => %{
            "fill" => "rgba(17, 76, 167, 0.11)",
            "stroke" => "rgba(90, 67, 20, 0.18)",
            "opacity" => 0.56
          }
        }
      )
    end)
  end

  defp overview_graph?(assigns) do
    active_face(assigns) == "graph" and
      is_nil(assigns.node_focus_target_id) and
      is_nil(assigns.selected_agent_id) and
      is_nil(assigns.subtree_root_id) and
      not assigns.show_null_results? and
      not assigns.filter_to_null_results?
  end

  defp elem_or(tuple, index), do: Enum.at(tuple, index)

  defp assemble_face(nodes, conduits) do
    nodes_by_id = Map.new(nodes, &{&1["id"], &1})
    entries = Enum.map(nodes, &node_entry/1)

    commands =
      Enum.flat_map(entries, & &1.commands) ++
        Enum.flat_map(conduits, &conduit_commands(&1, nodes_by_id))

    markers = Enum.map(entries, & &1.marker)
    {commands, markers}
  end

  defp node_entry(node) do
    node_id = node["id"]
    status = node["status"] || "available"
    position = node["position"] || [0, 0, 0]
    size = node["size"] || [1, 1, 1]
    geometry = node["geometry"] || "cube"
    target_id = node_id
    meta = Map.get(node, "meta", %{})
    command_id = node["commandId"] || "#{node_id}:body"
    custom_commands = Map.get(node, "commands")

    marker =
      SceneSpec.marker(target_id,
        label: node["label"] || node_id,
        action_label: node["actionLabel"],
        sigil: node["sigil"],
        kind: node["kind"],
        status: status,
        intent: node["intent"] || "scene_action",
        back_target_id: node["backTargetId"],
        history_key: node["historyKey"],
        group_role: node["groupRole"],
        click_tone: node["clickTone"],
        meta: meta,
        command_id: command_id
      )

    intent_style = SceneSpec.intent_style(SceneSpec.node_style(status), node["intent"])

    commands =
      if is_list(custom_commands) do
        custom_commands
      else
        case geometry do
          "socket" ->
            [
              SceneSpec.add_sphere(
                command_id,
                SceneSpec.sphere_center(position, size),
                SceneSpec.sphere_radius(size),
                style: intent_style,
                target_id: target_id,
                scale: node["scale"] || SceneSpec.socket_scale(size, status),
                scale_origin: node["scaleOrigin"] || [0.5, 1, 0.5]
              )
            ]

          "carved_cube" ->
            [
              SceneSpec.add_box(
                command_id,
                position,
                size,
                style: intent_style,
                target_id: target_id
              ),
              SceneSpec.remove_box(
                "#{node_id}:carve",
                SceneSpec.inset_position(position),
                SceneSpec.inset_size(size),
                style: SceneSpec.carved_wall_style(status),
                target_id: target_id
              )
            ]

          "ghost" ->
            [
              SceneSpec.add_box(
                command_id,
                position,
                size,
                style: SceneSpec.ghost_style(),
                opaque: false,
                target_id: target_id
              )
            ]

          "reliquary" ->
            [
              SceneSpec.add_box(
                command_id,
                position,
                size,
                style: intent_style,
                target_id: target_id,
                scale: node["scale"] || [0.88, 0.92, 0.88],
                scale_origin: node["scaleOrigin"] || [0.5, 1, 0.5]
              )
            ]

          "monolith" ->
            [
              SceneSpec.add_box(
                command_id,
                position,
                size,
                style: intent_style,
                target_id: target_id,
                scale: node["scale"] || [0.9, 1, 0.9],
                scale_origin: node["scaleOrigin"] || [0.5, 1, 0.5]
              )
            ]

          _ ->
            [
              SceneSpec.add_box(
                command_id,
                position,
                size,
                style: intent_style,
                opaque: Map.get(node, "opaque"),
                target_id: target_id,
                scale: SceneSpec.default_scale(node, status),
                scale_origin: SceneSpec.default_scale_origin(node, status)
              )
            ]
        end
      end

    %{commands: commands, marker: marker}
  end

  defp conduit_commands(conduit, nodes_by_id) do
    custom_commands = Map.get(conduit, "commands")

    case custom_commands do
      commands when is_list(commands) ->
        commands

      _ ->
        with from_node when is_map(from_node) <- Map.get(nodes_by_id, conduit["from"]),
             to_node when is_map(to_node) <- Map.get(nodes_by_id, conduit["to"]) do
          base =
            SceneSpec.add_line(
              "#{conduit["id"]}:line",
              SceneSpec.anchor(Map.fetch!(from_node, "position"), Map.fetch!(from_node, "size")),
              SceneSpec.anchor(Map.fetch!(to_node, "position"), Map.fetch!(to_node, "size")),
              radius: conduit["radius"] || 0.75,
              shape: conduit["shape"] || "rounded",
              style: SceneSpec.conduit_style(conduit["state"] || "visible")
            )

          waypoints =
            conduit
            |> Map.get("waypoints", [])
            |> Enum.with_index()
            |> Enum.map(fn {point, index} ->
              SceneSpec.add_sphere(
                "#{conduit["id"]}:waypoint:#{index}",
                point,
                0.6,
                style: SceneSpec.conduit_style(conduit["state"] || "visible")
              )
            end)

          [base | waypoints]
        else
          _ -> []
        end
    end
  end
end
