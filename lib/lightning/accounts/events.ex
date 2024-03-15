defmodule Lightning.Accounts.Events do
  @moduledoc """
  Publishes and subscribe to events related to user accounts.
  """

  @topic "users:all"

  defmodule UserRegistered do
    @moduledoc false
    defstruct user: nil
  end

  def user_registered(user) do
    Lightning.broadcast(
      @topic,
      %UserRegistered{user: user}
    )
  end

  def subscribe do
    Lightning.subscribe(@topic)
  end
end
