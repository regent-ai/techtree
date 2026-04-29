defmodule TechTree.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :tech_tree
  @schema "techtree"
  @migration_source "schema_migrations_techtree"

  def migrate do
    load_app()
    configure_repo_for_migrations!()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          create_schema!(repo)
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    configure_repo_for_migrations!()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        create_schema!(repo)
        Ecto.Migrator.run(repo, :down, to: version)
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end

  defp configure_repo_for_migrations! do
    direct_url = System.fetch_env!("DATABASE_DIRECT_URL")

    Enum.each(repos(), fn repo ->
      config =
        repo.config()
        |> Keyword.put(:url, direct_url)
        |> Keyword.put(:ssl, true)
        |> Keyword.put(:prepare, :unnamed)
        |> Keyword.put(:pool_size, String.to_integer(System.get_env("ECTO_POOL_SIZE") || "5"))
        |> Keyword.put(:migration_default_prefix, @schema)
        |> Keyword.put(:migration_source, @migration_source)

      Application.put_env(@app, repo, config)
    end)
  end

  defp create_schema!(repo) do
    Ecto.Adapters.SQL.query!(repo, ~s(CREATE SCHEMA IF NOT EXISTS "#{@schema}"), [])
  end
end
