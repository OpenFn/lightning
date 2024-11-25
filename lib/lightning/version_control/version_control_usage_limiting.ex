defmodule Lightning.VersionControl.VersionControlUsageLimiting do
  alias Lightning.Extensions.UsageLimiting

  @callback limit_github_sync(project_id :: Ecto.UUID.t() | nil) ::
          :ok | {:error, UsageLimiting.message()}

end
