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
  alias Lightning.Invocation.Dataclip
  alias Lightning.Projects.Environment
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Workflows.Workflow

  require Logger

  @type error_reason ::
          :not_found
          | :environment_not_configured
          | :project_not_found
          | :environment_mismatch
          | Credentials.oauth_refresh_error()
          | term()

  @type resolve_error :: {error_reason(), Credential.t() | nil}

  @type keychain_selectors :: %{
          Ecto.UUID.t() => String.t() | nil | :invalid_path
        }

  @doc """
  Resolves a credential for a run by matching the project's environment,
  or resolves a credential directly for a specific environment.

  For a run, keychain credentials are selected from `keychain_selectors` (see
  `keychain_selectors/1`). When it is `nil` they are read from the run's
  stored input.
  """
  @spec resolve_credential(
          Run.t(),
          credential_id :: String.t(),
          keychain_selectors() | nil
        ) ::
          {:ok, ResolvedCredential.t() | nil}
          | {:error, :not_found | resolve_error()}
  @spec resolve_credential(Credential.t(), environment :: String.t()) ::
          {:ok, ResolvedCredential.t()}
          | {:error, resolve_error()}
  def resolve_credential(
        run_or_credential,
        id_or_environment,
        keychain_selectors \\ nil
      )

  def resolve_credential(%Credential{} = credential, environment, nil) do
    case Credentials.resolve_credential_body(credential, environment) do
      {:ok, body} ->
        {:ok, ResolvedCredential.from(credential, body)}

      {:error, reason} ->
        log_resolution_error(reason)
        {:error, {reason, credential}}
    end
  end

  def resolve_credential(%Run{} = run, id, keychain_selectors) do
    Logger.metadata(run_id: run.id, credential_id: id)

    with {:ok, project_env} <- get_project_env(run),
         credential when not is_nil(credential) <- get_run_credential(run, id),
         {:ok, credential} <-
           select_credential(credential, run, keychain_selectors) do
      if credential,
        do: resolve_credential_with_env(credential, run, project_env),
        else: {:ok, nil}
    else
      nil ->
        {:error, :not_found}

      {:error, :environment_not_configured} ->
        {:error, {:environment_not_configured, nil}}

      {:error, :project_not_found} ->
        {:error, {:project_not_found, nil}}

      {:error, :keychain_input_unavailable} ->
        {:error, {:keychain_input_unavailable, nil}}

      {:error, :invalid_keychain_path} ->
        {:error, {:invalid_keychain_path, nil}}
    end
  end

  @doc """
  Reads, for each keychain the run's jobs use, the external id its path selects
  from the run's input.

  Projects that don't save dataclips have the input wiped as soon as the worker
  fetches it, which is before it asks for any credential. Call this before the
  wipe and pass the result to `resolve_credential/3`.
  """
  @spec keychain_selectors(Run.t()) :: keychain_selectors()
  def keychain_selectors(%Run{} = run) do
    %{snapshot: %{jobs: jobs}, dataclip_id: dataclip_id} =
      Repo.preload(run, :snapshot)

    keychain_ids =
      for %{keychain_credential_id: id} <- jobs, id, uniq: true, do: id

    keychain_selectors(dataclip_id, keychain_ids)
  end

  defp keychain_selectors(_dataclip_id, []), do: %{}

  defp keychain_selectors(dataclip_id, keychain_ids) do
    # One query per keychain, so a path Postgres can't parse or evaluate only
    # breaks the job that uses it, not every keychain in the run.
    Map.new(keychain_ids, &{&1, select_external_id(dataclip_id, &1)})
  end

  defp select_external_id(dataclip_id, keychain_id) do
    from(k in KeychainCredential,
      join: d in Dataclip,
      on: d.id == ^dataclip_id,
      where: k.id == ^keychain_id,
      select:
        fragment(
          "jsonb_path_query_first(?, ?::jsonpath) #>> '{}'",
          d.body,
          k.path
        )
    )
    |> Repo.one()
  rescue
    Postgrex.Error -> :invalid_path
  end

  defp select_credential(%Credential{} = credential, _run, _selectors),
    do: {:ok, credential}

  defp select_credential(%KeychainCredential{} = keychain, run, nil),
    do:
      select_credential(
        keychain,
        run,
        keychain_selectors(run.dataclip_id, [keychain.id])
      )

  defp select_credential(%KeychainCredential{} = keychain, run, selectors) do
    case Map.fetch(selectors, keychain.id) do
      {:ok, :invalid_path} ->
        log_resolution_error(:invalid_keychain_path,
          keychain_id: keychain.id,
          path: keychain.path
        )

        {:error, :invalid_keychain_path}

      {:ok, external_id} ->
        {:ok,
         find_credential_by_external_id(run, external_id) ||
           keychain.default_credential}

      :error ->
        log_resolution_error(:keychain_input_unavailable)
        {:error, :keychain_input_unavailable}
    end
  end

  defp resolve_credential_with_env(%Credential{} = credential, _run, project_env) do
    case Credentials.resolve_credential_body(credential, project_env) do
      {:ok, body} ->
        {:ok, ResolvedCredential.from(credential, body)}

      {:error, :environment_not_found} ->
        log_resolution_error(:environment_mismatch, project_env: project_env)
        {:error, {:environment_mismatch, credential}}

      {:error, reason} ->
        log_resolution_error(reason)
        {:error, {reason, credential}}
    end
  end

  @spec get_project_env(Run.t()) :: {:ok, String.t()} | {:error, term()}
  defp get_project_env(%Run{} = run) do
    case Environment.fetch(run) do
      {:ok, env} ->
        {:ok, env}

      {:error, reason} ->
        log_resolution_error(reason)
        {:error, reason}
    end
  end

  defp find_credential_by_external_id(_run, nil), do: nil

  defp find_credential_by_external_id(run, external_id) do
    from(
      c in Ecto.assoc(run, [
        :work_order,
        :workflow,
        :project,
        :project_credentials,
        :credential
      ]),
      where: c.external_id == ^external_id
    )
    |> Repo.one()
  end

  @spec get_run_credential(Run.t(), String.t()) ::
          Credential.t() | KeychainCredential.t() | nil
  defp get_run_credential(%Run{} = run, id) do
    # The worker was given the credential ids in the run's snapshot, so that is
    # what it may ask for, even if the live workflow has changed since.
    %{snapshot: %{workflow_id: workflow_id, jobs: jobs}} =
      Repo.preload(run, :snapshot)

    project_credential_ids =
      for %{project_credential_id: pc_id} <- jobs, pc_id, do: pc_id

    keychain_ids =
      for %{keychain_credential_id: k_id} <- jobs, k_id, do: k_id

    from(c in Credential,
      join: pc in assoc(c, :project_credentials),
      join: w in Workflow,
      on: w.id == ^workflow_id and pc.project_id == w.project_id,
      where: c.id == ^id and pc.id in ^project_credential_ids
    )
    |> Repo.one() || get_run_keychain(workflow_id, id, keychain_ids)
  end

  defp get_run_keychain(workflow_id, id, keychain_ids) do
    # The default credential is joined through the project this run belongs to,
    # not off what the stored id implies and not through the keychain's own
    # project. The write-time guard can only speak for rows written after it;
    # this speaks for every row, including any already in the database from
    # before the guard worked, or written by a path that bypasses the changeset
    # entirely.
    #
    # Anchoring on the run rather than on the keychain matters. A job holding a
    # keychain from another project would otherwise satisfy this check, since
    # that keychain's default really is shared with that other project, and the
    # worker would be handed a credential its own project was never given. It
    # is the same project keychain selection resolves against, so the two
    # halves cannot disagree.
    from(k in KeychainCredential,
      join: w in Workflow,
      on: w.id == ^workflow_id,
      left_join: default_cred in assoc(k, :default_credential),
      left_join: default_pc in ProjectCredential,
      on:
        default_pc.credential_id == default_cred.id and
          default_pc.project_id == w.project_id,
      where: k.id == ^id and k.id in ^keychain_ids,
      select: {k, default_cred, not is_nil(default_pc.id)}
    )
    |> Repo.one()
    |> case do
      {keychain, default_cred, in_project?} ->
        %{keychain | default_credential: (in_project? && default_cred) || nil}

      nil ->
        nil
    end
  end

  defp log_resolution_error(reason, metadata \\ [])

  defp log_resolution_error(:project_not_found, meta),
    do: Logger.error("Project not found for run", meta)

  defp log_resolution_error(:environment_not_configured, meta),
    do: Logger.warning("Project has no environment configured", meta)

  defp log_resolution_error(:environment_mismatch, meta),
    do:
      Logger.warning(
        "Credential environment does not match project environment",
        meta
      )

  defp log_resolution_error(:reauthorization_required, meta),
    do: Logger.info("OAuth refresh token has expired", meta)

  defp log_resolution_error(:temporary_failure, meta),
    do: Logger.info("Could not reach the OAuth provider", meta)

  defp log_resolution_error(:keychain_input_unavailable, meta),
    do:
      Logger.warning(
        "Keychain input was wiped before this channel could read it",
        meta
      )

  defp log_resolution_error(:invalid_keychain_path, meta),
    do:
      Logger.warning(
        "Keychain path could not be evaluated against the run's input",
        meta
      )

  defp log_resolution_error(_reason, _meta), do: :ok
end
