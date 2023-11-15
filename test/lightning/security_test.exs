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

    test "does not change the field when it is not the password" do
      message = ~S[{"a":1, "otherfield":"password"}]
      timestamp = DateTime.utc_now()

      assert %Changeset{
               changes: %{
                 message: ^message,
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
  end
end
