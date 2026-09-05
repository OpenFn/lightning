defmodule Lightning.Projects.MailRecipients do
  @moduledoc """
  Whether a person may be sent a project's contents by email.

  Being sent a project's contents is the same standing as opening them in the
  app, so this asks `:access_project` rather than deciding again — one call
  covering the project existing, it not winding down, the person holding
  standing in it, and the MFA requirement.

  Account state is what `:access_project` does not carry. The request path
  learns it at authentication, which a cron job and a run-completion callback
  never reach. An unconfirmed address counts for more here than it does there,
  because nothing has established that the mailbox belongs to the member.

  Only for mail carrying a project's own contents — run logs, digests,
  retention notices. Account mail must not be routed through this: the notice
  that an account is being deleted has to reach an account this refuses.
  """
  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project

  @doc """
  Whether `user` may be sent `project`'s contents.
  """
  @spec may_receive?(Project.t(), User.t()) :: boolean()
  def may_receive?(%Project{} = project, %User{} = user) do
    not Accounts.login_blocked?(user) and
      not Accounts.locked_out?(user) and
      Permissions.can?(:project_users, :access_project, user, project)
  end
end
