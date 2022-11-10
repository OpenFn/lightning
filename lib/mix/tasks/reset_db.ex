defmodule Mix.Tasks.ResetDb do
  @moduledoc "The reset_db mix task: `mix help reset_db`"
  use Mix.Task

  import Ecto.Query
  alias Lightning.InvocationReasons
  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Credentials.Audit
  alias LightningWeb.AuthProvidersLive
  alias Lightning.AuthProviders
  alias Lightning.AttemptRun
  alias Lightning.Attempt
  alias Lightning.WorkOrder
  alias Lightning.InvocationReason
  alias Lightning.Repo
  alias Lightning.Accounts.User
  alias Lightning.Projects.{Project, ProjectCredential, ProjectUser}
  alias Lightning.Credentials.Credential
  alias Lightning.Workflows.Workflow
  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Trigger

  @shortdoc "Deletes everything in the db except the migrations"
  def run(_) do
    Mix.Task.run("app.start")

    IO.inspect("Tearing database down ...")

    Repo.delete_all(Lightning.Attempt)
    Repo.delete_all(Lightning.AttemptRun)
    Repo.delete_all(Lightning.AuthProviders.AuthConfig)
    Repo.delete_all(Lightning.Credentials.Audit)
    Repo.delete_all(Lightning.Credentials.Audit.Metadata)
    Repo.delete_all(Lightning.Credentials.Credential)
    Repo.delete_all(Lightning.Invocation.Dataclip)
    Repo.delete_all(Lightning.Invocation.Run)
    Repo.delete_all(Lightning.InvocationReason)
    Repo.delete_all(Lightning.Jobs.Job)
    Repo.delete_all(Lightning.Jobs.Trigger)
    Repo.delete_all(Lightning.Projects.Project)
    Repo.delete_all(Lightning.Projects.ProjectCredential)
    Repo.delete_all(Lightning.Projects.ProjectUser)
    Repo.delete_all(Lightning.WorkOrder)
    Repo.delete_all(Lightning.Workflows.Workflow)
    Repo.delete_all(Lightning.Accounts.UserToken)
    Repo.delete_all(Lightning.Accounts.User)

    IO.inspect("Done.")
  end
end
