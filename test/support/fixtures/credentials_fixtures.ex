defmodule Lightning.CredentialsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Credentials` context.
  """

  @doc """
  Generate a credential.
  """
  def credential_fixture(attrs \\ %{}) do
    {:ok, credential} =
      attrs
      |> Enum.into(%{
        body: %{},
        name: "some name"
      })
      |> Lightning.Credentials.create_credential()

    credential
  end
end
