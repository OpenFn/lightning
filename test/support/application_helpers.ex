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

  @doc """
  In situations where you need to wait for something to complete, 
  e.g a Task, you can use this to create a dynamic delay which
  will return as soon as the success function returns a positive
  result.
  """
  def dynamically_absorb_delay(success_function, opts \\ []) do
    iterations = opts |> Keyword.get(:iterations, 30)
    sleep = opts |> Keyword.get(:sleep, 1)

    Enum.take_while(1..iterations, fn _index ->
      if success_function.() do
        false
      else
        Process.sleep(sleep)
        true
      end
    end)
  end
end
