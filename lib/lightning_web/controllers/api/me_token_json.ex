defmodule LightningWeb.API.MeTokenJSON do
  @moduledoc """
  A person's personal access tokens. A listed token shows only its first and
  last five characters; only the answer that creates one shows it whole.
  """
  alias Lightning.Accounts.UserToken

  @shown 5

  def index(%{tokens: tokens}),
    do: %{data: Enum.map(tokens, &entry(&1, mask(&1.token)))}

  def create(%{token: token}), do: %{data: entry(token, token.token)}

  defp entry(%UserToken{} = token, shown) do
    %{
      id: token.id,
      token: shown,
      inserted_at: token.inserted_at,
      last_used_at: token.last_used_at
    }
  end

  defp mask(token),
    do:
      String.slice(token, 0, @shown) <>
        "…" <> String.slice(token, -@shown, @shown)
end
