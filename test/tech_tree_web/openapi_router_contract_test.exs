defmodule TechTreeWeb.OpenApiRouterContractTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Techtree.Contracts.Check

  test "OpenAPI paths match owned Phoenix routes" do
    contract_routes = Check.contract_routes!("docs/api-contract.openapiv3.yaml")
    router_routes = Check.router_routes!()

    assert MapSet.difference(contract_routes, router_routes) == MapSet.new()
    assert MapSet.difference(router_routes, contract_routes) == MapSet.new()
  end

  test "network-facing runtime contract does not expose local workspace path routes" do
    contract_routes = Check.contract_routes!("docs/api-contract.openapiv3.yaml")

    refute Enum.any?(contract_routes, fn {verb, path} ->
             verb != "GET" and String.starts_with?(path, "/v1/runtime/")
           end)

    refute MapSet.member?(contract_routes, {"POST", "/v1/agent/runtime/compile/artifact"})
    refute MapSet.member?(contract_routes, {"POST", "/v1/agent/runtime/compile/run"})
    refute MapSet.member?(contract_routes, {"POST", "/v1/agent/runtime/compile/review"})
    refute MapSet.member?(contract_routes, {"POST", "/v1/agent/runtime/pin"})
    refute MapSet.member?(contract_routes, {"POST", "/v1/agent/runtime/publish/prepare"})
  end

  test "agent runtime write contract requires agent authentication" do
    operations = contract_operations!("docs/api-contract.openapiv3.yaml")

    operations
    |> Enum.filter(fn {{verb, path}, _body} ->
      verb != "GET" and String.starts_with?(path, "/v1/agent/runtime/")
    end)
    |> Enum.each(fn {{_verb, _path}, body} ->
      assert body =~ "security: [{ AgentSiwaHeaders: [] }]"
    end)
  end

  defp contract_operations!(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({nil, nil, %{}}, fn line, {current_path, current_operation, operations} ->
      cond do
        path = openapi_path(line) ->
          {path, nil, operations}

        verb = openapi_verb(line) ->
          operation = {String.upcase(verb), current_path}
          {current_path, operation, Map.put(operations, operation, [])}

        is_tuple(current_operation) ->
          {current_path, current_operation,
           Map.update!(operations, current_operation, &[line | &1])}

        true ->
          {current_path, current_operation, operations}
      end
    end)
    |> elem(2)
    |> Map.new(fn {operation, lines} ->
      {operation, lines |> Enum.reverse() |> Enum.join("\n")}
    end)
  end

  defp openapi_path(line) do
    case Regex.run(~r/^  (\/[^:]+):\s*$/, line) do
      [_, path] -> path
      _ -> nil
    end
  end

  defp openapi_verb(line) do
    case Regex.run(~r/^    (get|post|put|patch|delete):\s*$/, line) do
      [_, verb] -> verb
      _ -> nil
    end
  end
end
