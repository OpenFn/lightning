defmodule Lightning.CredentialsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Credentials` context.
  """

  def credential_attrs(attrs \\ []) when is_list(attrs) do
    Keyword.put_new_lazy(attrs, :user_id, fn ->
      Lightning.AccountsFixtures.user_fixture().id
    end)
    |> Enum.into(%{
      body: %{},
      name: "some name"
    })
  end

  @doc """
  Generate a credential.
  """
  @spec credential_fixture(attrs :: Keyword.t()) ::
          Lightning.Credentials.Credential.t()
  def credential_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, credential} =
      credential_attrs(attrs)
      |> Lightning.Credentials.create_credential()

    credential
  end

  def project_credential_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, credential} =
      Lightning.Credentials.update_credential(
        credential_fixture(attrs)
        |> Lightning.Repo.preload(:project_credentials),
        %{
          project_credentials: [
            %{
              project_id:
                attrs[:project_id] ||
                  Lightning.ProjectsFixtures.project_fixture().id
            }
          ]
        }
      )

    credential
    |> Map.get(:project_credentials)
    |> List.first()
  end
end
