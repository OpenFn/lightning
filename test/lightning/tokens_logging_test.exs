defmodule Lightning.TokensLoggingTest do
  @moduledoc """
  Asserts the log line `Tokens.safe_peek/1` emits, reading the `:logger` event
  directly rather than through `ExUnit.CaptureLog`.

  `CaptureLog` installs and removes a handler per capture, and under this
  suite's global `capture_log: true` those captures intermittently close empty —
  several unrelated modules fail the same way in a full run. A handler of our
  own is not part of that contention, and filtering on the message means a log
  line from a concurrent test satisfies the same assertion rather than racing it.
  """
  use ExUnit.Case, async: true

  import Lightning.TokenHelpers, only: [jwt_with_payload: 1]

  alias Lightning.Tokens

  @message "Token could not be read"

  setup do
    :ok =
      :logger.add_handler(__MODULE__, __MODULE__, %{config: %{pid: self()}})

    on_exit(fn -> :logger.remove_handler(__MODULE__) end)
  end

  test "the exception behind a malformed-token refusal is logged" do
    # The rescue in safe_peek/1 is deliberately broad, so a genuine fault — a
    # Joken bug, an unrelated raise — would otherwise leave nothing but a quiet
    # 401. Warning rather than error: garbage tokens are routine, and Sentry's
    # LoggerHandler captures error.
    assert Tokens.verify(jwt_with_payload("notjson")) ==
             {:error, :token_malformed}

    assert_receive {:logged, level, _message},
                   1_000,
                   "the broad rescue swallowed an exception without logging it, so a real " <>
                     "fault in token reading would surface only as a 401."

    assert level == :warning,
           "the token-read failure logged at #{inspect(level)} rather than warning."
  end

  @doc false
  def log(%{level: level, msg: msg}, %{config: %{pid: pid}}) do
    message = render(msg)

    if String.contains?(message, @message) do
      send(pid, {:logged, level, message})
    end

    :ok
  end

  defp render({:string, chardata}), do: IO.chardata_to_string(chardata)
  defp render({:report, report}), do: inspect(report)

  defp render({format, args}) when is_list(format) or is_binary(format),
    do: format |> :io_lib.format(args) |> IO.chardata_to_string()

  defp render(other), do: inspect(other)
end
