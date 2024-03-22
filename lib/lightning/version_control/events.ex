defmodule Lightning.VersionControl.Events do
  defmodule OauthTokenAdded do
    @moduledoc false
    defstruct user: nil
  end

  defmodule OauthTokenFailed do
    @moduledoc false
    defstruct [:user, :error_response]
  end

  def oauth_token_added(user) do
    Lightning.broadcast(
      topic(user.id),
      %OauthTokenAdded{user: user}
    )
  end

  def oauth_token_failed(user, error_resp) do
    Lightning.broadcast(
      topic(user.id),
      %OauthTokenFailed{user: user, error_response: error_resp}
    )
  end

  def subscribe(%Lightning.Accounts.User{id: id}) do
    Lightning.subscribe(topic(id))
  end

  defp topic(id), do: "version_control_events:#{id}"
end
