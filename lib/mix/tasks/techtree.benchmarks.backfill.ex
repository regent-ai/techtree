defmodule Mix.Tasks.Techtree.Benchmarks.Backfill do
  @moduledoc false
  use Mix.Task

  @shortdoc "Backfills BBH and Science Task records into benchmark capsules"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [domain: :string, dry_run: :boolean],
        aliases: [d: :domain]
      )

    domain = Keyword.get(opts, :domain, "all")
    dry_run? = Keyword.get(opts, :dry_run, false)

    case run_backfill(domain, dry_run?) do
      {:ok, results} ->
        Mix.shell().info("Benchmark backfill complete")
        Mix.shell().info("Domain: #{domain}")
        Mix.shell().info("Dry run: #{dry_run?}")
        Mix.shell().info("Results: #{inspect(results)}")

      {:error, reason} ->
        Mix.raise("Benchmark backfill failed: #{inspect(reason)}")
    end
  end

  defp run_backfill("all", dry_run?) do
    with {:ok, bbh} <- TechTree.Benchmarks.Importers.BBH.backfill_all(dry_run: dry_run?),
         {:ok, science_tasks} <-
           TechTree.Benchmarks.Importers.ScienceTasks.backfill_all(dry_run: dry_run?) do
      {:ok, %{bbh: bbh, science_tasks: science_tasks}}
    end
  end

  defp run_backfill("bbh", dry_run?) do
    with {:ok, bbh} <- TechTree.Benchmarks.Importers.BBH.backfill_all(dry_run: dry_run?) do
      {:ok, %{bbh: bbh}}
    end
  end

  defp run_backfill("science_tasks", dry_run?) do
    with {:ok, science_tasks} <-
           TechTree.Benchmarks.Importers.ScienceTasks.backfill_all(dry_run: dry_run?) do
      {:ok, %{science_tasks: science_tasks}}
    end
  end

  defp run_backfill("science", dry_run?), do: run_backfill("science_tasks", dry_run?)

  defp run_backfill(other, _dry_run?), do: {:error, {:unknown_domain, other}}
end
