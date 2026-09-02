defmodule Lightning.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """

  require Logger

  @app :lightning
  @repo Lightning.Repo

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def create_db do
    @repo.__adapter__().storage_up(@repo.config)
    |> case do
      :ok ->
        Logger.info("Database created successfully")
        :ok

      {:error, :already_up} ->
        Logger.info("Database already up.")
        :ok

      {:error, e} ->
        Logger.error("Encountered an error during database creation")
        Logger.error(e)
        {:error, e}
    end
  end

  @doc """
  Populate the adaptor catalogue from a JSON snapshot file, without
  reaching npm. This is the release equivalent of
  `mix lightning.adaptors.import` — a release has no Mix, so run this
  through `bin/lightning eval` instead.

  ## Usage

      bin/lightning eval 'Lightning.Release.seed_adaptors("/path/to/snapshot.json")'
      bin/lightning eval 'Lightning.Release.seed_adaptors("/path/to/snapshot.json", replace: true)'
  """
  def seed_adaptors(path, opts \\ []) do
    load_app()

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(@repo, fn _repo ->
        Lightning.Adaptors.seed_from_file(path, opts)
      end)

    result
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  def load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(@repo)
  end
end
