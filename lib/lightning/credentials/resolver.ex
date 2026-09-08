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
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Run

  require Logger

  @type error_reason ::
          :not_found
          | :no_credential_grant
          | Credentials.oauth_refresh_error()
          | term()

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

  def resolve_credential(%Run{} = run, id) do
    Logger.metadata(run_id: run.id, credential_id: id)

    case get_run_credential(run, id) do
      nil -> {:error, :not_found}
      credential -> resolve_granted(credential, run)
    end
  end

  def resolve_credential(%Credential{} = credential, environment) do
    case Credentials.resolve_credential_body(credential, environment) do
      {:ok, body} ->
        {:ok, ResolvedCredential.from(credential, body)}

      {:error, reason} ->
        log_resolution_error(reason)
        {:error, {reason, credential}}
    end
  end

  # The run's project decides which values it may read, and it decides that by
  # the grant recorded on its share of this credential. Not by its environment
  # name: a name is typed on the project settings screen, by someone who may
  # have no standing on the credential, and matching it at run time is what let
  # a sandbox read its parent's production values.
  defp resolve_granted(%Credential{} = credential, run) do
    body_id = granted_body_id(run, credential)

    case Credentials.resolve_granted_body(credential, body_id) do
      {:ok, body} ->
        {:ok, ResolvedCredential.from(credential, body)}

      {:error, :no_credential_grant} ->
        log_resolution_error(:no_credential_grant)
        {:error, {:no_credential_grant, credential}}

      {:error, reason} ->
        log_resolution_error(reason)
        {:error, {reason, credential}}
    end
  end

  defp resolve_granted(%KeychainCredential{} = keychain, run) do
    credential =
      find_credential_by_jsonpath(run, keychain.path) ||
        keychain.default_credential

    # A keychain picks which credential to spend from the run's own data, so the
    # grant that applies is the run's project's grant on whichever one it picked.
    # Falling back to the default when that credential has no grant would swap
    # one secret for another silently, so it does not.
    if credential do
      resolve_granted(credential, run)
    else
      {:ok, nil}
    end
  end

  # nil for a share that exists with no grant and for no share at all. Both mean
  # the same thing: this project was never given these values.
  defp granted_body_id(%Run{} = run, %Credential{id: credential_id}) do
    from(pc in ProjectCredential,
      join: w in Lightning.Workflows.Workflow,
      on: w.project_id == pc.project_id,
      join: wo in Lightning.WorkOrder,
      on: wo.workflow_id == w.id,
      join: r in Run,
      on: r.work_order_id == wo.id,
      where: r.id == ^run.id and pc.credential_id == ^credential_id,
      select: pc.credential_body_id
    )
    |> Repo.one()
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
    # The default credential is joined through the project this run belongs to,
    # not off what the stored id implies and not through the keychain's own
    # project. The
    # write-time guard can only speak for rows written after it; this speaks
    # for every row, including any already in the database from before the
    # guard worked, or written by a path that bypasses the changeset entirely.
    #
    # Anchoring on the run rather than on the keychain matters. A job holding a
    # keychain from another project would otherwise satisfy this check, since
    # that keychain's default really is shared with that other project, and the
    # worker would be handed a credential its own project was never given. It
    # is the same project the jsonpath branch above resolves against, so the
    # two halves cannot disagree.
    from(j in Ecto.assoc(run, [:work_order, :workflow, :jobs]),
      left_join: w in assoc(j, :workflow),
      left_join: c in assoc(j, :credential),
      left_join: k in assoc(j, :keychain_credential),
      left_join: default_cred in assoc(k, :default_credential),
      left_join: default_pc in ProjectCredential,
      on:
        default_pc.credential_id == default_cred.id and
          default_pc.project_id == w.project_id,
      where: c.id == ^id or k.id == ^id,
      select: %{
        credential: c,
        keychain: k,
        default_credential: default_cred,
        default_credential_in_project?: not is_nil(default_pc.id)
      }
    )
    |> Repo.one()
    |> case do
      %{credential: %Credential{} = credential, keychain: nil} ->
        credential

      %{
        credential: nil,
        keychain: %KeychainCredential{} = keychain,
        default_credential: default_cred,
        default_credential_in_project?: in_project?
      } ->
        %{keychain | default_credential: (in_project? && default_cred) || nil}

      nil ->
        nil
    end
  end

  defp log_resolution_error(reason, metadata \\ [])

  defp log_resolution_error(:no_credential_grant, meta),
    do:
      Logger.warning(
        "Project has not been granted any values for this credential",
        meta
      )

  defp log_resolution_error(:reauthorization_required, meta),
    do: Logger.info("OAuth refresh token has expired", meta)

  defp log_resolution_error(:temporary_failure, meta),
    do: Logger.info("Could not reach the OAuth provider", meta)

  defp log_resolution_error(_reason, _meta), do: :ok
end
