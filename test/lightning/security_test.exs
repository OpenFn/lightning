defmodule Lightning.SecurityTest do
  use ExUnit.Case

  alias Lightning.Invocation.LogLine
  alias Lightning.Security
  alias Ecto.Changeset

  describe "redact_password/1" do
    test "replaces the password with ***" do
      message = ~S[{"a":1, "password":"secret"}]
      timestamp = DateTime.utc_now()

      assert %Changeset{
               changes: %{
                 message: ~S[{"a":1, "password":"***"}],
                 timestamp: ^timestamp
               }
             } =
               %LogLine{id: Ecto.UUID.generate()}
               |> Changeset.cast(%{message: message, timestamp: timestamp}, [
                 :message,
                 :timestamp
               ])
               |> Security.redact_password(:message)
    end

    test "doesn't add change when the changeset is invalid" do
      message = ~S[{"a":1, "password":"same value"}]
      timestamp = DateTime.utc_now()

      assert %Changeset{
               changes: %{
                 timestamp: ^timestamp
               }
             } =
               %LogLine{id: Ecto.UUID.generate()}
               |> Changeset.cast(%{timestamp: timestamp}, [:timestamp])
               |> Map.put(:valid?, false)
               |> Changeset.cast(%{message: message}, [:message])
               |> Security.redact_password(:message)
    end
  end
end
