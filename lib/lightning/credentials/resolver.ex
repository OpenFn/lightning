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
  @moduledoc """
  Provides credential resolution abstraction for workflow execution.

  Handles the complexities of preparing credentials for worker consumption,
  including OAuth token refresh, credential body merging, and empty value cleanup.
  Supports regular credentials, OAuth credentials, and future keychain credentials.

  Returns a ResolvedCredential containing the final worker-ready body and original
  credential reference for scrubbing setup.
  """
  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.ResolvedCredential
  alias Lightning.Repo
  alias Lightning.Run

  require Logger

  @type error_reason :: :not_found | Credentials.oauth_refresh_error()
  @type resolve_error :: {error_reason(), Credential.t()}

  @doc """
  Resolves a credential into a ResolvedCredential ready for worker consumption.

  Can be called with either:
  - `resolve_credential(credential)` for direct credential resolution
  - `resolve_credential(run, id)` for credential lookup and resolution

  For regular credentials, returns the body as-is.
  For OAuth credentials, refreshes tokens if needed and merges into body.
  """
  @spec resolve_credential(Credential.t()) ::
          {:ok, ResolvedCredential.t()} | {:error, resolve_error()}
  def resolve_credential(%Credential{schema: "oauth"} = credential) do
    case Credentials.maybe_refresh_token(credential) do
      {:ok, credential} ->
        {:ok, ResolvedCredential.from(credential)}

      {:error, reason} ->
        {:error, {reason, credential}}
    end
  end

  @spec resolve_credential(Credential.t()) :: {:ok, ResolvedCredential.t()}
  def resolve_credential(%Credential{} = credential) do
    resolved_credential = ResolvedCredential.from(credential)
    {:ok, resolved_credential}
  end

  @spec resolve_credential(Run.t(), credential_id :: String.t()) ::
          {:ok, ResolvedCredential.t() | nil}
          | {:error, :not_found | resolve_error()}
  def resolve_credential(%Run{} = run, id) do
    Logger.info("Resolving credential #{id} for run #{run.id}")

    case get_run_credential(run, id) do
      %Credential{} = credential ->
        resolve_credential(credential)

      %KeychainCredential{} = keychain ->
        resolve_keychain_credential(keychain, run)

      nil ->
        {:error, :not_found}
    end
  end

  @spec resolve_keychain_credential(KeychainCredential.t(), Run.t()) ::
          {:ok, ResolvedCredential.t() | nil} | {:error, resolve_error()}
  defp resolve_keychain_credential(
         %KeychainCredential{} = keychain,
         %Run{} = run
       ) do
    credential =
      find_credential_by_jsonpath(run, keychain.path) ||
        keychain.default_credential

    # Find credential by external_id within the same project using JSONPath extraction
    if credential do
      resolve_credential(credential)
    else
      {:ok, nil}
    end
  end

  @spec find_credential_by_jsonpath(Run.t(), String.t()) ::
          Credential.t() | nil
  defp find_credential_by_jsonpath(
         %Run{dataclip_id: dataclip_id} = run,
         jsonpath
       ) do
    get_external_id_query =
      from(d in Lightning.Invocation.Dataclip,
        where: d.id == ^dataclip_id,
        select:
          fragment(
            "jsonb_path_query_first(?, ?::jsonpath) #>> '{}'",
            d.body,
            type(^jsonpath, :string)
          )
      )

    from(
      c in Ecto.assoc(run, [
        :workflow,
        :project,
        :project_credentials,
        :credential
      ]),
      where: c.external_id == subquery(get_external_id_query)
    )
    |> Repo.one()
  end

  @spec get_run_credential(Run.t(), String.t()) ::
          Credential.t() | KeychainCredential.t() | nil
  defp get_run_credential(%Run{} = run, id) do
    from(j in Ecto.assoc(run, [:workflow, :jobs]),
      left_join: c in assoc(j, :credential),
      left_join: k in assoc(j, :keychain_credential),
      left_join: default_cred in assoc(k, :default_credential),
      where: c.id == ^id or k.id == ^id,
      select: %{
        credential: c,
        keychain: k,
        default_credential: default_cred
      }
    )
    |> Repo.one()
    |> case do
      %{credential: %Credential{} = credential, keychain: nil} ->
        credential

      %{
        credential: nil,
        keychain: %KeychainCredential{} = keychain,
        default_credential: default_cred
      } ->
        %{keychain | default_credential: default_cred}

      nil ->
        nil
    end
  end
end
