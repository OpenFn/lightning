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

  @doc """
  Captures `:info` log messages emitted by `fun`, alongside its return value.

  The test logger level is `:warning` (see `config/test.exs`), which gates
  `:info` messages at the primary `:logger` level before any capture handler
  sees them. Per-process levels (`Logger.put_process_level/2`) can only restrict
  below the primary level, not lift above it, so the primary level has to be
  lowered for the duration of the capture and restored afterwards.
  """
  def capture_info_log(fun) do
    previous_level = Logger.level()
    Logger.configure(level: :info)

    try do
      ExUnit.CaptureLog.with_log([level: :info], fun)
    after
      Logger.configure(level: previous_level)
    end
  end
end
