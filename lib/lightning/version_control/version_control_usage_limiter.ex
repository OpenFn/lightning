defmodule Lightning.VersionControl.VersionControlUsageLimiter do
  @moduledoc false

  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Services.UsageLimiter

  @spec limit_github_sync(project_id :: Ecto.UUID.t()) ::
          :ok | {:error, UsageLimiting.message()}
  def limit_github_sync(project_id) do
    case UsageLimiter.limit_action(%Action{type: :github_sync}, %Context{
           project_id: project_id
         }) do
      :ok ->
        :ok

      {:error, _reason, error} ->
        {:error, error}
    end
  end
end
