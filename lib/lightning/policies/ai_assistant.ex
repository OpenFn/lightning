defmodule Lightning.Policies.AiAssistant do
  @moduledoc """
  The Bodyguard Policy module for the AI assistant's sessions and messages.

  Only a session token of Lightning's own app may use the assistant, since a
  person has to accept its disclaimer before anything is sent to it, so every
  other token is refused before the project is consulted. Step-up isn't
  needed. Nothing checks the disclaimer itself yet; see
  `LightningWeb.API.AiSessionController`.

  On the project, any member may read the project's sessions and chat in them,
  viewers included, as the app's channel lets them. That is the project's
  `:access_project` rule in `Lightning.Policies.ProjectUsers`, with its
  standing, MFA and scheduled deletion checks.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Scope

  @type actions :: :read_ai_sessions | :chat

  @spec authorize(actions(), Scope.t(), Scope.subject() | :before_target) ::
          Decision.answer()
  def authorize(action, %Scope{} = scope, subject)
      when action in [:read_ai_sessions, :chat],
      do:
        Decision.session(
          scope,
          ProjectUsers.authorize(:access_project, scope, subject)
        )
end
