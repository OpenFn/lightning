defmodule Lightning.Credentials.CredentialTest do
  use Lightning.DataCase

  alias Lightning.Credentials.Credential

  describe "changeset/2" do
    test "name can't be blank" do
      errors = Credential.changeset(%Credential{}, %{}) |> errors_on()
      assert errors[:name] == ["can't be blank"]
      assert errors[:body] == ["can't be blank"]
    end
  end
end
