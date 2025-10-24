defmodule Lightning.Credentials.ResolvedCredential do
  @moduledoc """
  Represents a credential that has been resolved and is ready for worker consumption.

  Contains the final body for the specific environment and maintains reference
  to the original credential for scrubbing setup.
  """
  alias Lightning.Credentials.Credential

  defstruct [:body, :credential]

  @type t :: %__MODULE__{
          body: map(),
          credential: Credential.t()
        }

  @doc """
  Creates a ResolvedCredential from a Credential with a specific body.
  """
  def from(credential, body) when is_map(body) do
    %__MODULE__{
      body: remove_empty_values(body),
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

  Resolves credentials by matching the project's environment to the credential's
  environment body. For OAuth credentials, passes the environment body during
  token refresh.
  """
  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.ResolvedCredential
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Run

  require Logger

  @type error_reason ::
          :not_found
          | :environment_not_configured
          | :project_not_found
          | :environment_mismatch
          | Credentials.oauth_refresh_error()

  @type resolve_error :: {error_reason(), Credential.t() | nil}

  @doc """
  Resolves a credential for a run by matching the project's environment,
  or resolves a credential directly for a specific environment.
  """
  @spec resolve_credential(Run.t(), credential_id :: String.t()) ::
          {:ok, ResolvedCredential.t() | nil}
          | {:error, :not_found | resolve_error()}
  @spec resolve_credential(Credential.t(), environment :: String.t()) ::
          {:ok, ResolvedCredential.t()}
          | {:error, resolve_error()}

  def resolve_credential(a, b \\ "main")

  def resolve_credential(%Run{} = run, id) do
    Logger.metadata(run_id: run.id, credential_id: id)

    with {:ok, project_env} <- get_project_env(run),
         credential when not is_nil(credential) <- get_run_credential(run, id) do
      resolve_credential_with_env(credential, run, project_env)
    else
      nil ->
        {:error, :not_found}

      {:error, :environment_not_configured} ->
        {:error, {:environment_not_configured, nil}}

      {:error, :project_not_found} ->
        {:error, {:project_not_found, nil}}
    end
  end

  def resolve_credential(%Credential{} = credential, environment) do
    case Credentials.resolve_credential_body(credential, environment) do
      {:ok, body} ->
        {:ok, ResolvedCredential.from(credential, body)}

      {:error, reason} ->
        {:error, {reason, credential}}
    end
  end

  defp resolve_credential_with_env(%Credential{} = credential, _run, project_env) do
    case Credentials.resolve_credential_body(credential, project_env) do
      {:ok, body} ->
        {:ok, ResolvedCredential.from(credential, body)}

      {:error, :environment_not_found} ->
        Logger.error(
          "Credential environment does not match project environment",
          project_env: project_env
        )

        {:error, {:environment_mismatch, credential}}

      {:error, reason} ->
        {:error, {reason, credential}}
    end
  end

  defp resolve_credential_with_env(
         %KeychainCredential{} = keychain,
         run,
         project_env
       ) do
    credential =
      find_credential_by_jsonpath(run, keychain.path) ||
        keychain.default_credential

    if credential do
      resolve_credential_with_env(credential, run, project_env)
    else
      {:ok, nil}
    end
  end

  @spec get_project_env(Run.t()) :: {:ok, String.t()} | {:error, term()}
  defp get_project_env(%Run{} = run) do
    case Lightning.Projects.get_project_for_run(run) do
      %Project{env: nil, parent_id: nil} ->
        Logger.warning(
          "Root project has no environment set, defaulting to 'main'"
        )

        {:ok, "main"}

      %Project{env: env} when is_binary(env) ->
        {:ok, env}

      %Project{env: nil} ->
        Logger.error("Project has no environment configured")
        {:error, :environment_not_configured}

      nil ->
        Logger.error("Project not found for run")
        {:error, :project_not_found}
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
        :work_order,
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
    from(j in Ecto.assoc(run, [:work_order, :workflow, :jobs]),
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
