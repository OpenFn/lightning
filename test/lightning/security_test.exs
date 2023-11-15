defmodule Lightning.SecurityTest do
  use ExUnit.Case

  alias Lightning.Invocation.LogLine
  alias Lightning.Security
  alias Ecto.Changeset

  describe "redact_password/1" do
    test "replaces the password with ***" do
      id = Ecto.UUID.generate()
      message = ~S[{"a":1, "password":"secret"}]
      timestamp = DateTime.utc_now()

      assert ~S[{"a":1, "password":"***"}] ==
               %LogLine{id: id}
               |> Changeset.cast(%{message: message, timestamp: timestamp}, [
                 :message,
                 :timestamp
               ])
               |> Security.redact_password(:message)
               |> Changeset.get_change(:message)
    end
  end
end
