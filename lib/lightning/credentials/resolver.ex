defmodule Lightning.Credentials.ResolvedCredential do
  @moduledoc """
  Represents a credential that has been resolved and is ready for worker consumption.

  Contains the final merged body (for OAuth credentials) and maintains reference
  to the original credential for scrubbing setup.
  """
  alias Lightning.Credentials.Credential

  defstruct [:body, :credential]

  @type t :: %__MODULE__{
          body: map(),
          credential: Credential.t()
        }

  @doc """
  Creates a ResolvedCredential from a Credential, handling OAuth merging and empty value removal.
  """
  def from(%Credential{schema: "oauth"} = credential) do
    merged_body = Map.merge(credential.body, credential.oauth_token.body)

    %__MODULE__{
      body: remove_empty_values(merged_body),
      credential: credential
    }
  end

  def from(%Credential{} = credential) do
    %__MODULE__{
      body: remove_empty_values(credential.body),
      credential: credential
    }
  end

  defp remove_empty_values(body) when is_map(body) do
    Map.reject(body, &match?({_, ""}, &1))
  end
end

defmodule Lightning.Credentials.Resolver do
  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.ResolvedCredential
  alias Lightning.Repo
  alias Lightning.Run

  @doc """
  Resolves a credential into a ResolvedCredential ready for worker consumption.

  Can be called with either:
  - `resolve_credential(credential)` for direct credential resolution
  - `resolve_credential(run, id)` for credential lookup and resolution

  For regular credentials, returns the body as-is.
  For OAuth credentials, refreshes tokens if needed and merges into body.
  """
  def resolve_credential(%Credential{schema: "oauth"} = credential) do
    with {:ok, refreshed_credential} <-
           Credentials.maybe_refresh_token(credential) do
      resolved_credential = ResolvedCredential.from(refreshed_credential)
      {:ok, resolved_credential}
    else
      {:error, :reauthorization_required} ->
        {:error, %{type: :reauthorization_required, credential: credential}}

      {:error, :temporary_failure} ->
        {:error, %{type: :temporary_failure, credential: credential}}

      {:error, other_error} ->
        {:error,
         %{
           type: :oauth_error,
           credential: credential,
           original_error: other_error
         }}
    end
  end

  def resolve_credential(%Credential{} = credential) do
    resolved_credential = ResolvedCredential.from(credential)
    {:ok, resolved_credential}
  end

  def resolve_credential(%Run{} = run, id) do
    credential = get_run_credential(run, id)

    case credential do
      nil -> {:error, :not_found}
      credential -> resolve_credential(credential)
    end
  end

  defp get_run_credential(%Run{} = run, id) do
    from(c in Ecto.assoc(run, [:workflow, :jobs, :credential]),
      where: c.id == ^id
    )
    |> Repo.one()
  end
end
