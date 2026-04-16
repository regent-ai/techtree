defmodule TechTree.BBH.HelpersTest do
  use ExUnit.Case, async: true

  alias TechTree.BBH.Capsule
  alias TechTree.BBH.Helpers

  test "execution_defaults match the workspace materializer defaults" do
    capsule = %Capsule{
      capsule_id: "capsule_benchmark_001",
      split: "climb",
      provider_ref: "hypotest://bbh/climb",
      family_ref: "family-123"
    }

    defaults = Helpers.execution_defaults(capsule)

    assert defaults.solver == %{
             kind: "skydiscover",
             entrypoint: "uv run techtree-bbh sky-search",
             search_algorithm: "best_of_n"
           }

    assert defaults.evaluator == %{
             kind: "hypotest",
             dataset_ref: "hypotest://bbh/climb",
             benchmark_ref: "capsule_benchmark_001",
             scorer_version: "hypotest-v0.1"
           }

    assert defaults.workspace.best_program_path == "outputs/skydiscover/best_program.py"
    assert defaults.workspace.search_summary_path == "outputs/skydiscover/search_summary.json"
  end
end
