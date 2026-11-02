defmodule Lightning.Policies.Channels do
  @moduledoc """
  The Bodyguard Policy module for a project's channels and the requests
  recorded for them, on the API.

  Only people reach them, on a personal access token or a session token. The
  service account and a repo connection are refused with `false` whatever
  their grants, since `Lightning.Policies.Decision.person/2` decides first.

  The rules are the ones the Channels and History pages apply, read from
  `Lightning.Policies.ProjectUsers`:

    * `:access_channels` (listing and reading channels and their requests) is
      `:access_project`, any member.
    * `:write_channel` (creating or replacing one through `PUT`) is
      `:update_channel`, which allows the same owners, admins and editors as
      `:create_channel`.
    * `:delete_channel` is `:delete_channel`, owners, admins and editors.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Scope

  @type actions :: :access_channels | :write_channel | :delete_channel

  @spec authorize(actions(), Scope.t(), Scope.subject() | :before_target) ::
          Decision.answer()
  def authorize(action, %Scope{} = scope, subject),
    do:
      Decision.person(
        scope,
        ProjectUsers.authorize(rule(action), scope, subject)
      )

  defp rule(:access_channels), do: :access_project
  defp rule(:write_channel), do: :update_channel
  defp rule(:delete_channel), do: :delete_channel
end
