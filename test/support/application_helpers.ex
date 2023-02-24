defmodule Lightning.ApplicationHelpers do
  @doc """
  Temporary sets an application env to a given valid, and reverts it
  when the test exits/finishes.

  It is advisable to disable `:async` mode for the given test file as
  it can lead to leaky values between tests.
  """
  def put_temporary_env(app, key, value) do
    previous_value = Application.get_env(app, key)
    Application.put_env(app, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(app, key, previous_value)
    end)
  end
end
