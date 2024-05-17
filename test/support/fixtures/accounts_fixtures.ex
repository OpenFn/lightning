defmodule Lightning.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Accounts` context.
  """
  alias Lightning.Factories

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"
  def valid_first_name, do: "Anna"

  def valid_user_attributes(attrs \\ []) when is_list(attrs) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      first_name: valid_first_name(),
      last_name: "Last"
    })
  end

  def user_fixture(attrs \\ []) when is_list(attrs) do
    Factories.insert(:user, valid_user_attributes(attrs))
  end

  def superuser_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Lightning.Accounts.register_superuser()

    user
  end

  def api_token_fixture(user) do
    token = Lightning.Accounts.generate_api_token(user)
    Lightning.Repo.get_by(Lightning.Accounts.UserToken, token: token)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
