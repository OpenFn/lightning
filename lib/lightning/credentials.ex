defmodule Lightning.Credentials do
  @moduledoc """
  The Credentials context.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2, normalize_keys: 1]

  alias Ecto.Multi
  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserNotifier
  alias Lightning.Accounts.UserToken
  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.Credentials
  alias Lightning.Credentials.Audit
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.CredentialBody
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthValidation
  alias Lightning.Credentials.SchemaDocument
  alias Lightning.Credentials.SensitiveValues
  alias Lightning.Projects.Project
  alias Lightning.Repo

  require Logger

  @type transfer_error :: :token_error | :not_found | :not_owner
  @type oauth_refresh_error :: :temporary_failure | :reauthorization_required

  @doc """
  Perform, when called with %{"type" => "purge_deleted"}
  will find credentials that are ready for permanent deletion, set their bodies
  to null, and try to purge them.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    credentials_to_update =
      from(c in Credential,
        where: c.scheduled_deletion <= ago(0, "second")
      )
      |> Repo.all()

    credentials_with_empty_body =
      for credential <- credentials_to_update,
          {:ok, updated_credential} <- [clear_credential_bodies(credential)],
          do: updated_credential

    credentials_to_delete =
      Enum.filter(credentials_with_empty_body, fn credential ->
        !has_activity_in_projects?(credential)
      end)

    deleted_count =
      Enum.reduce(credentials_to_delete, 0, fn credential, acc ->
        case delete_credential(credential) do
          :ok -> acc + 1
          _error -> acc
        end
      end)

    {:ok, %{deleted_count: deleted_count}}
  end

  defp clear_credential_bodies(credential) do
    credential = Repo.preload(credential, :credential_bodies)

    Enum.each(credential.credential_bodies, fn cb ->
      CredentialBody.changeset(cb, %{body: %{}})
      |> Repo.update()
    end)

    {:ok, Repo.reload!(credential) |> Repo.preload(:credential_bodies)}
  end

  @doc """
  Retrieves all credentials based on the given context, either a Project or a User.

  ## Parameters
    - context: The Project or User struct to retrieve credentials for.

  ## Returns
    - A list of credentials associated with the given Project or created by the given User.

  ## Examples
    When given a Project:

      iex> list_credentials(%Project{id: 1})
      [%Credential{project_id: 1}, %Credential{project_id: 1}]

    When given a User:

      iex> list_credentials(%User{id: 123})
      [%Credential{user_id: 123}, %Credential{user_id: 123}]
  """
  @spec list_credentials(Project.t()) :: [Credential.t()]
  def list_credentials(%Project{} = project) do
    query =
      from c in Credential,
        join: pc in assoc(c, :project_credentials),
        on: pc.project_id == ^project.id,
        preload: [
          :user,
          :project_credentials,
          :projects,
          :credential_bodies,
          :oauth_client
        ],
        order_by: [asc: fragment("lower(?)", c.name)],
        group_by: c.id

    Repo.all(query)
  end

  @spec list_credentials(User.t()) :: [Credential.t()]
  def list_credentials(%User{id: user_id}) do
    list_credentials_query(user_id)
    |> order_by([c], asc: fragment("lower(?)", c.name))
    |> Repo.all()
  end

  defp list_credentials_query(user_id) do
    from(c in Credential,
      where: c.user_id == ^user_id,
      preload: [:projects, :user, :credential_bodies, :oauth_client]
    )
  end

  @doc """
  Gets a single credential.

  Raises `Ecto.NoResultsError` if the Credential does not exist.

  ## Examples

      iex> get_credential!(123)
      %Credential{}

      iex> get_credential!(456)
      ** (Ecto.NoResultsError)

  """
  def get_credential!(id), do: Repo.get!(Credential, id)

  def get_credential(id), do: Repo.get(Credential, id)

  def get_credential_by_project_credential(project_credential_id) do
    query =
      from c in Credential,
        join: pc in assoc(c, :project_credentials),
        on: pc.id == ^project_credential_id

    Repo.one(query)
  end

  @doc """
  Gets a credential body for a specific environment.

  Returns nil if no body exists for the given credential and environment combination.

  ## Examples

      iex> get_credential_body(credential_id, "production")
      %CredentialBody{name: "production", body: %{...}}

      iex> get_credential_body(credential_id, "nonexistent")
      nil
  """
  @spec get_credential_body(String.t(), String.t()) :: CredentialBody.t() | nil
  def get_credential_body(credential_id, env_name) do
    from(cb in CredentialBody,
      where: cb.credential_id == ^credential_id and cb.name == ^env_name
    )
    |> Repo.one()
  end

  @doc """
  Creates a new credential with its credential bodies.

  ## Parameters
    * `attrs` - Map of attributes for the credential including:
      * `user_id` - User ID (required)
      * `name` - Credential name (required)
      * `schema` - Schema type (e.g., "oauth", "raw", etc.)
      * `oauth_client_id` - OAuth client ID (for OAuth credentials)
      * `credential_bodies` - List of credential body maps, each containing:
        * `name` - Environment name (e.g., "production", "staging")
        * `body` - Credential configuration data
      * `expected_scopes` - List of expected scopes (for OAuth credentials)

  ## Returns
    * `{:ok, credential}` - Successfully created credential
    * `{:error, error}` - Error with creation process
  """
  @spec create_credential(map()) :: {:ok, Credential.t()} | {:error, any()}
  def create_credential(attrs \\ %{}) do
    attrs = normalize_keys(attrs)
    credential_bodies = get_credential_bodies(attrs)

    with :ok <- validate_credential_bodies(credential_bodies, attrs),
         changeset <- change_credential(%Credential{}, attrs) do
      build_create_multi(changeset, credential_bodies)
      |> derive_events(changeset)
      |> Repo.transaction()
      |> handle_transaction_result(changeset)
    end
  end

  defp build_create_multi(changeset, credential_bodies) do
    multi = Multi.new() |> Multi.insert(:credential, changeset)

    schema_name = Ecto.Changeset.get_field(changeset, :schema)

    credential_bodies
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {body_attrs, index}, acc ->
      acc
      |> Multi.insert(:"credential_body_#{index}", fn %{credential: credential} ->
        %CredentialBody{}
        |> CredentialBody.changeset(%{
          credential_id: credential.id,
          name: body_attrs["name"],
          body: body_attrs["body"]
        })
        |> cast_credential_body_change(schema_name)
      end)
    end)
  end

  @doc """
  Updates an existing credential and its credential bodies.

  ## Parameters
    * `credential` - The credential to update
    * `attrs` - Map of attributes to update, including:
      * `credential_bodies` - List of credential body maps to create/update

  ## Returns
    * `{:ok, credential}` - Successfully updated credential
    * `{:error, error}` - Error with update process
  """
  @spec update_credential(Credential.t(), map()) ::
          {:ok, Credential.t()} | {:error, any()}
  def update_credential(%Credential{} = credential, attrs) do
    attrs = normalize_keys(attrs)

    credential_bodies =
      attrs
      |> get_credential_bodies()
      |> then(fn bodies ->
        if credential.schema == "oauth" do
          preserve_refresh_tokens(bodies, credential)
        else
          bodies
        end
      end)

    with :ok <-
           validate_credential_bodies(
             credential_bodies,
             attrs,
             credential.schema
           ),
         changeset <- change_credential(credential, attrs) do
      build_update_multi(credential, changeset, credential_bodies)
      |> derive_events(changeset)
      |> Repo.transaction()
      |> handle_transaction_result(changeset)
    end
  end

  defp build_update_multi(credential, changeset, credential_bodies) do
    schema_name = Ecto.Changeset.get_field(changeset, :schema)
    delete_environments = Map.get(changeset.params, "delete_environments", [])

    Multi.new()
    |> Multi.update(:credential, changeset)
    |> add_environment_deletions(credential.id, delete_environments)
    |> add_credential_body_upserts(credential.id, credential_bodies, schema_name)
  end

  defp add_environment_deletions(multi, _credential_id, []), do: multi

  defp add_environment_deletions(multi, credential_id, delete_environments) do
    Enum.reduce(delete_environments, multi, fn env_name, acc ->
      Multi.run(acc, :"delete_env_#{env_name}", fn _repo, _changes ->
        delete_credential_body_if_exists(credential_id, env_name)
      end)
    end)
  end

  defp delete_credential_body_if_exists(credential_id, env_name) do
    case Repo.get_by(CredentialBody,
           credential_id: credential_id,
           name: env_name
         ) do
      nil ->
        {:ok, :not_found}

      credential_body ->
        Repo.delete(credential_body)
        {:ok, :deleted}
    end
  end

  defp add_credential_body_upserts(multi, _credential_id, [], _schema_name),
    do: multi

  defp add_credential_body_upserts(
         multi,
         credential_id,
         credential_bodies,
         schema_name
       ) do
    credential_bodies
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {body_attrs, index}, acc ->
      Multi.run(acc, :"credential_body_#{index}", fn _repo, _changes ->
        upsert_credential_body(credential_id, body_attrs, schema_name)
      end)
    end)
  end

  defp upsert_credential_body(credential_id, body_attrs, schema_name) do
    environment_name = body_attrs["name"]
    body_data = body_attrs["body"]

    case Repo.get_by(CredentialBody,
           credential_id: credential_id,
           name: environment_name
         ) do
      nil ->
        %CredentialBody{}
        |> CredentialBody.changeset(%{
          credential_id: credential_id,
          name: environment_name,
          body: body_data
        })
        |> cast_credential_body_change(schema_name)
        |> Repo.insert()

      credential_body ->
        credential_body
        |> CredentialBody.changeset(%{body: body_data})
        |> cast_credential_body_change(schema_name)
        |> Repo.update()
    end
  end

  defp get_credential_bodies(attrs) do
    case Map.get(attrs, "credential_bodies") do
      nil ->
        []

      bodies when is_list(bodies) ->
        Enum.map(bodies, &normalize_body_attrs/1)

      _ ->
        []
    end
  end

  defp normalize_body_attrs(body_attrs) when is_map(body_attrs) do
    body_attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> then(fn attrs ->
      env_name = attrs["name"]
      body_data = attrs["body"]
      actual_body = extract_actual_body(body_data, env_name)

      %{"name" => env_name, "body" => actual_body}
    end)
    |> coerce_json_field("body")
  end

  defp extract_actual_body(%{} = body_data, env_name)
       when is_map_key(body_data, env_name) do
    parse_nested_value(Map.get(body_data, env_name))
  end

  defp extract_actual_body(map, _env_name) when is_map(map), do: map

  defp extract_actual_body(_, _env_name), do: %{}

  defp parse_nested_value(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end

  defp parse_nested_value(map) when is_map(map), do: map

  defp parse_nested_value(_), do: %{}

  defp validate_credential_bodies(credential_bodies, attrs, schema \\ nil) do
    credential_schema = schema || Map.get(attrs, "schema")

    if credential_schema == "oauth" do
      credential_bodies
      |> Enum.reduce_while(:ok, fn body_attrs, _acc ->
        case validate_oauth_body(body_attrs["body"], attrs) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      :ok
    end
  end

  defp validate_oauth_body(body_data, attrs) do
    with {:ok, _} <- OauthValidation.validate_token_data(body_data) do
      validate_expected_scopes(body_data, attrs)
    end
  end

  defp validate_expected_scopes(token_data, attrs) do
    expected_scopes = get_expected_scopes(attrs)

    if Enum.empty?(expected_scopes) do
      :ok
    else
      OauthValidation.validate_scope_grant(token_data, expected_scopes)
    end
  end

  defp get_expected_scopes(attrs) do
    scopes =
      Map.get(attrs, "expected_scopes") || Map.get(attrs, :expected_scopes) || []

    case scopes do
      list when is_list(list) -> list
      binary when is_binary(binary) -> String.split(binary, " ", trim: true)
      _ -> []
    end
  end

  @doc false
  def handle_transaction_result(transaction_result, credential_changeset) do
    case transaction_result do
      {:error, :credential, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, op, %Ecto.Changeset{} = body_changeset, _changes} ->
        # When a credential_body operation fails, we need to return
        # a Credential changeset with the error, not a CredentialBody changeset.
        # Extract which environment failed from the operation name.
        env_index =
          op
          |> Atom.to_string()
          |> String.replace("credential_body_", "")
          |> String.to_integer()

        errors = body_changeset.errors

        changeset_with_errors =
          Enum.reduce(errors, credential_changeset, fn {field, {msg, opts}},
                                                       acc ->
            Ecto.Changeset.add_error(
              acc,
              :credential_bodies,
              "Environment #{env_index + 1}: #{field} #{msg}",
              opts
            )
          end)

        {:error, changeset_with_errors}

      {:error, _op, error, _changes} ->
        {:error, error}

      {:ok, %{credential: credential}} ->
        {:ok,
         credential
         |> Repo.reload!()
         |> Repo.preload([
           :user,
           :project_credentials,
           :projects,
           :credential_bodies
         ])}
    end
  end

  @doc """
  Creates a credential schema from credential json schema.
  """
  @spec get_schema(String.t()) :: Credentials.Schema.t()
  def get_schema(schema_name) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    File.read("#{schemas_path}/#{schema_name}.json")
    |> case do
      {:ok, raw_json} ->
        Credentials.Schema.new(raw_json, schema_name)

      {:error, reason} ->
        raise "Error reading credential schema. Got: #{reason |> inspect()}"
    end
  end

  defp cast_credential_body_change(
         %Ecto.Changeset{valid?: true, changes: %{body: body}} = changeset,
         schema_name
       ) do
    case put_typed_body(body, schema_name) do
      {:ok, updated_body} ->
        Ecto.Changeset.put_change(changeset, :body, updated_body)

      {:error, _reason} ->
        Ecto.Changeset.add_error(changeset, :body, "Invalid body types")
    end
  end

  defp cast_credential_body_change(changeset, _schema_name), do: changeset

  defp put_typed_body(body, schema_name)
       when schema_name in ["raw", "oauth"],
       do: {:ok, body}

  defp put_typed_body(body, schema_name) do
    schema = get_schema(schema_name)

    with changeset <- SchemaDocument.changeset(body, schema: schema),
         {:ok, typed_body} <- Ecto.Changeset.apply_action(changeset, :insert) do
      updated_body =
        Enum.into(typed_body, body, fn {field, typed_value} ->
          {to_string(field), typed_value}
        end)

      {:ok, updated_body}
    end
  end

  defp extract_environment_bodies(changes) do
    Enum.reduce(changes, [], fn
      {key, credential_body}, acc when is_atom(key) ->
        case Atom.to_string(key) do
          "credential_body_" <> _ ->
            [{credential_body.name, credential_body.body} | acc]

          _ ->
            acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp derive_events(
         multi,
         %Ecto.Changeset{data: %Credential{__meta__: %{state: state}}} =
           changeset
       ) do
    case changeset.changes do
      map when map_size(map) == 0 ->
        multi

      _ ->
        project_credentials_multi =
          Ecto.Changeset.get_change(changeset, :project_credentials, [])
          |> Enum.reduce(Multi.new(), fn changeset, multi ->
            derive_event(multi, changeset)
          end)

        multi
        |> Multi.run(:collect_env_bodies, fn _repo, changes ->
          {:ok, extract_environment_bodies(changes)}
        end)
        |> Multi.insert(
          :audit,
          fn %{credential: credential, collect_env_bodies: env_bodies} ->
            Audit.user_initiated_event(
              if(state == :built, do: "created", else: "updated"),
              credential,
              changeset,
              env_bodies
            )
          end
        )
        |> Multi.append(project_credentials_multi)
    end
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :delete,
           data: %Lightning.Projects.ProjectCredential{}
         } = changeset
       ) do
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{credential: credential} ->
        Audit.user_initiated_event(
          "removed_from_project",
          credential,
          %{
            before: %{
              project_id: Ecto.Changeset.get_field(changeset, :project_id)
            },
            after: %{project_id: nil}
          }
        )
      end
    )
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :insert,
           data: %Lightning.Projects.ProjectCredential{}
         } = changeset
       ) do
    project_id = Ecto.Changeset.get_field(changeset, :project_id)

    multi
    |> Multi.insert(
      {:audit, project_id},
      fn %{credential: credential} ->
        Audit.user_initiated_event("added_to_project", credential, %{
          before: %{project_id: nil},
          after: %{project_id: project_id}
        })
      end
    )
    |> Multi.run(
      {:propagate_to_descendants, project_id},
      fn _repo, %{credential: credential} ->
        propagate_credential_to_descendants(credential.id, project_id)
      end
    )
  end

  defp derive_event(multi, %Ecto.Changeset{
         action: :update,
         data: %Lightning.Projects.ProjectCredential{}
       }) do
    multi
  end

  @spec propagate_credential_to_descendants(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp propagate_credential_to_descendants(credential_id, project_id) do
    current_time = DateTime.utc_now() |> DateTime.truncate(:second)

    credential_rows =
      Lightning.Projects.list_workspace_projects(project_id)
      |> Map.get(:descendants, [])
      |> Enum.map(fn descendant ->
        %{
          project_id: descendant.id,
          credential_id: credential_id,
          inserted_at: current_time,
          updated_at: current_time
        }
      end)

    {count, _} =
      Repo.insert_all(
        Lightning.Projects.ProjectCredential,
        credential_rows,
        on_conflict: :nothing,
        conflict_target: [:project_id, :credential_id]
      )

    {:ok, count}
  end

  @doc """
  Deletes a credential.

  ## Examples

      iex> delete_credential(credential)
      {:ok, %Credential{}}

      iex> delete_credential(credential)
      {:error, %Ecto.Changeset{}}

  """
  def delete_credential(%Credential{} = credential) do
    Multi.new()
    |> Multi.delete(:credential, credential)
    |> Multi.insert(:audit, fn _ ->
      Audit.user_initiated_event("deleted", credential)
    end)
    |> Repo.transaction()
  end

  @doc """
  Schedules a given credential for deletion.

  The deletion date is determined based on the `:purge_deleted_after_days` configuration
  in the application environment. If this configuration is absent, the credential is scheduled
  for immediate deletion.

  The function will also perform necessary side effects such as:
    - Removing associations of the credential.
    - Revoking OAuth tokens if the credential is an OAuth credential.
    - Notifying the owner of the credential about the scheduled deletion.

  ## Parameters

    - `credential`: A `Credential` struct that is to be scheduled for deletion.

  ## Returns

    - `{:ok, credential}`: Returns an `:ok` tuple with the updated credential struct if the
      update was successful.
    - `{:error, changeset}`: Returns an `:error` tuple with the changeset if the update failed.

  ## Examples

      iex> schedule_credential_deletion(%Credential{id: some_id})
      {:ok, %Credential{}}

      iex> schedule_credential_deletion(%Credential{})
      {:error, %Ecto.Changeset{}}

  """
  def schedule_credential_deletion(%Credential{} = credential) do
    changeset =
      Credential.changeset(credential, %{
        "scheduled_deletion" => scheduled_deletion_date()
      })

    Multi.new()
    |> Multi.update(:credential, changeset)
    |> Multi.run(:preloaded, fn repo, %{credential: cred} ->
      {:ok, repo.preload(cred, [:credential_bodies, :oauth_client])}
    end)
    |> Multi.run(:associations, fn _repo, %{preloaded: cred} ->
      remove_credential_associations(cred)
      {:ok, cred}
    end)
    |> Multi.run(:revoke_oauth, fn _repo, %{preloaded: cred} ->
      maybe_revoke_oauth_tokens(cred)
      {:ok, cred}
    end)
    |> Multi.run(:notify, fn _repo, %{preloaded: cred} ->
      notify_owner(cred)
      {:ok, cred}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{preloaded: updated_credential}} ->
        {:ok, updated_credential}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp scheduled_deletion_date do
    days = Lightning.Config.purge_deleted_after_days() || 0
    DateTime.utc_now() |> Timex.shift(days: days)
  end

  def cancel_scheduled_deletion(credential_id) do
    get_credential!(credential_id)
    |> update_credential(%{
      scheduled_deletion: nil
    })
  end

  defp maybe_revoke_oauth_tokens(%Credential{schema: "oauth"} = credential) do
    if credential.oauth_client_id do
      client = Repo.get(OauthClient, credential.oauth_client_id)

      if client && client.revocation_endpoint do
        credential.credential_bodies
        |> Enum.each(fn credential_body ->
          revoke_oauth_token(credential, client, credential_body)
        end)
      end
    end

    :ok
  end

  defp maybe_revoke_oauth_tokens(_credential), do: :ok

  defp revoke_oauth_token(credential, client, credential_body) do
    case OauthHTTPClient.revoke_token(client, credential_body.body) do
      :ok ->
        revocation_metadata = %{
          client_id: client.id,
          revocation_endpoint: client.revocation_endpoint,
          environment: credential_body.name,
          success: true
        }

        credential = Repo.preload(credential, :user)

        audit_changeset =
          Audit.oauth_token_revoked_event(credential, revocation_metadata)

        save_audit_event(audit_changeset)

        Logger.info(
          "Successfully revoked OAuth token for environment: #{credential_body.name}"
        )

        :ok

      {:error, error} ->
        revocation_metadata = %{
          client_id: client.id,
          revocation_endpoint: client.revocation_endpoint,
          environment: credential_body.name,
          success: false,
          error: inspect(error)
        }

        credential = Repo.preload(credential, :user)

        audit_changeset =
          Audit.oauth_token_revoked_event(credential, revocation_metadata)

        save_audit_event(audit_changeset)

        Logger.warning(
          "Failed to revoke OAuth token for environment #{credential_body.name}: #{inspect(error)}"
        )

        :ok
    end
  end

  defp save_audit_event(audit_changeset) do
    case Repo.insert(audit_changeset) do
      {:ok, _audit} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to save audit event: #{inspect(changeset.errors)}")
        :ok
    end
  end

  defp remove_credential_associations(%Credential{id: credential_id}) do
    project_credential_ids_query =
      from(pc in Lightning.Projects.ProjectCredential,
        where: pc.credential_id == ^credential_id,
        select: pc.id
      )

    project_credential_ids = Repo.all(project_credential_ids_query)

    from(j in Lightning.Workflows.Job,
      where: j.project_credential_id in ^project_credential_ids
    )
    |> Repo.update_all(set: [project_credential_id: nil])

    Ecto.assoc(%Credential{id: credential_id}, :project_credentials)
    |> Repo.delete_all()
  end

  defp notify_owner(credential) do
    credential
    |> Repo.preload(:user)
    |> Map.get(:user)
    |> UserNotifier.send_credential_deletion_notification_email(credential)
  end

  @doc """
  Checks if a given `Credential` has any associated `Step` activity.

  ## Parameters

    - `_credential`: A `Credential` struct. Only the `id` field is used by the function.

  ## Returns

    - `true` if there's at least one `Step` associated with the given `Credential`.
    - `false` otherwise.

  ## Examples

      iex> has_activity_in_projects?(%Credential{id: some_id})
      true

      iex> has_activity_in_projects?(%Credential{id: another_id})
      false

  ## Notes

  This function leverages the association between `Step` and `Credential` to
  determine if any steps exist for a given credential. It's a fast check that
  does not load any records into memory, but simply checks for their existence.

  """
  def has_activity_in_projects?(%Credential{id: id} = _credential) do
    from(step in Lightning.Invocation.Step,
      where: step.credential_id == ^id
    )
    |> Repo.exists?()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking credential changes.

  ## Examples

      iex> change_credential(credential)
      %Ecto.Changeset{data: %Credential{}}

  """
  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(credential, attrs |> normalize_keys())
  end

  @doc """
  Extracts sensitive values from a credential body map.

  ## Examples

      iex> sensitive_values_from_body(%{"password" => "secret123"})
      ["secret123"]
  """
  @spec sensitive_values_from_body(map() | nil) :: [any()]
  def sensitive_values_from_body(body) when is_map(body) do
    SensitiveValues.secret_values(body)
  end

  def sensitive_values_from_body(_), do: []

  @doc """
  Extracts basic auth strings from a credential body map.

  ## Examples

      iex> basic_auth_from_body(%{"username" => "user", "password" => "pass"})
      ["dXNlcjpwYXNz"]
  """
  @spec basic_auth_from_body(map() | nil) :: [String.t()]
  def basic_auth_from_body(body) when is_map(body) do
    usernames = body |> Map.take(["username", "email"]) |> Map.values()
    password = Map.get(body, "password", "")

    usernames
    |> Enum.zip(List.duplicate(password, length(usernames)))
    |> Enum.map(fn {username, password} ->
      Base.encode64("#{username}:#{password}")
    end)
  end

  def basic_auth_from_body(_), do: []

  # Existing functions refactored to use the body-based functions
  @doc """
  Retrieves sensitive values for a credential in a specific environment.

  Used primarily for scrubbing historical dataclips where we need to look up
  the credential body by environment.

  ## Parameters
    - `id_or_credential`: Credential ID, Credential struct, or nil
    - `environment`: Environment name (defaults to "main")

  ## Examples

      iex> sensitive_values_for(credential, "production")
      ["secret123", "api_key_xyz"]
  """
  @spec sensitive_values_for(Ecto.UUID.t() | Credential.t() | nil, String.t()) ::
          [any()]
  def sensitive_values_for(id_or_credential, environment \\ "main")

  def sensitive_values_for(id, environment) when is_binary(id) do
    sensitive_values_for(get_credential!(id), environment)
  end

  def sensitive_values_for(nil, _environment), do: []

  def sensitive_values_for(%Credential{} = credential, environment) do
    credential = Repo.preload(credential, :credential_bodies)

    credential.credential_bodies
    |> Enum.find(fn cb -> cb.name == environment end)
    |> case do
      nil ->
        []

      credential_body ->
        sensitive_values_from_body(credential_body.body)
    end
  end

  @doc """
  Retrieves basic auth strings for a credential in a specific environment.

  Used primarily for scrubbing historical dataclips where we need to look up
  the credential body by environment.

  ## Parameters
    - `credential`: Credential struct or nil
    - `environment`: Environment name (defaults to "main")

  ## Examples

      iex> basic_auth_for(credential, "staging")
      ["dXNlcjpwYXNz"]
  """
  @spec basic_auth_for(Credential.t() | nil, String.t()) :: [String.t()]
  def basic_auth_for(credential, environment \\ "main")

  def basic_auth_for(nil, _environment), do: []

  def basic_auth_for(%Credential{} = credential, environment) do
    credential = Repo.preload(credential, :credential_bodies)

    credential.credential_bodies
    |> Enum.find(fn cb -> cb.name == environment end)
    |> case do
      nil -> []
      credential_body -> basic_auth_from_body(credential_body.body)
    end
  end

  @doc """
  Gets a credential body for an environment and refreshes OAuth tokens if expired.

  This is the primary function for credential resolution during workflow execution.
  It handles the full flow: fetch body → check expiration → refresh if needed → return final body.

  ## Parameters
    - `credential`: The credential struct
    - `environment`: Environment name (e.g., "production", "staging")

  ## Returns
    - `{:ok, body}` - The credential body (with fresh tokens if OAuth was refreshed)
    - `{:error, :environment_not_found}` - No body exists for this environment
    - `{:error, oauth_refresh_error()}` - OAuth refresh failed
  """
  @spec resolve_credential_body(Credential.t(), String.t()) ::
          {:ok, map()} | {:error, :environment_not_found | oauth_refresh_error()}
  def resolve_credential_body(%Credential{} = credential, environment) do
    case get_credential_body(credential.id, environment) do
      nil ->
        {:error, :environment_not_found}

      %CredentialBody{body: body} = credential_body ->
        if credential.schema == "oauth" && oauth_token_expired?(body) do
          credential
          |> Repo.preload(:oauth_client)
          |> refresh_credential_body_token(credential_body)
          |> case do
            {:ok, %CredentialBody{body: fresh_body}} ->
              {:ok, fresh_body}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:ok, body}
        end
    end
  end

  defp refresh_credential_body_token(credential, credential_body) do
    with {:ok, fresh_token} <-
           OauthHTTPClient.refresh_token(
             credential.oauth_client,
             credential_body.body
           ),
         scopes <- extract_scopes_or_default(fresh_token) do
      refresh_metadata = %{
        client_id: credential.oauth_client_id,
        environment: credential_body.name,
        scopes: scopes,
        expires_in: Map.get(fresh_token, "expires_in"),
        token_type: Map.get(fresh_token, "token_type", "Bearer")
      }

      audit_changeset =
        Audit.oauth_token_refreshed_event(credential, refresh_metadata)

      updated_token =
        Map.merge(credential_body.body, fresh_token)
        |> ensure_refresh_token_preserved(credential_body.body)
        |> normalize_token_expiry()

      case CredentialBody.changeset(credential_body, %{body: updated_token})
           |> Repo.update() do
        {:ok, updated_cb} ->
          save_audit_event(audit_changeset)
          {:ok, updated_cb}

        error ->
          error
      end
    else
      {:error, %{error: "invalid_grant"} = error_response} ->
        handle_oauth_refresh_failed(credential, credential_body, error_response)

      {:error, %{status: status} = error_response} when status in [400, 401] ->
        handle_oauth_refresh_failed(credential, credential_body, error_response)

      {:error, %{status: status} = error_response} when status in [429, 503] ->
        error_details =
          Map.take(error_response, [:status, :error, :details])
          |> Map.put(:error_type, "temporary_failure")
          |> Map.put(:client_id, credential.oauth_client_id)
          |> Map.put(:environment, credential_body.name)

        audit_changeset =
          Audit.oauth_token_refresh_failed_event(credential, error_details)

        save_audit_event(audit_changeset)
        {:error, :temporary_failure}

      {:error, error} ->
        audit_changeset =
          Audit.oauth_token_refresh_failed_event(
            credential,
            %{error: inspect(error), environment: credential_body.name}
          )

        save_audit_event(audit_changeset)
        {:error, error}
    end
  end

  defp ensure_refresh_token_preserved(merged_body, original_body) do
    if is_nil(merged_body["refresh_token"]) && original_body["refresh_token"] do
      Map.put(merged_body, "refresh_token", original_body["refresh_token"])
    else
      merged_body
    end
  end

  defp preserve_refresh_tokens(credential_bodies, credential) do
    existing_bodies =
      credential
      |> Repo.preload(:credential_bodies)
      |> Map.get(:credential_bodies)
      |> Enum.into(%{}, fn body -> {body.name, body} end)

    Enum.map(credential_bodies, fn body_attrs ->
      env_name = body_attrs["name"]
      new_body = body_attrs["body"]

      case Map.get(existing_bodies, env_name) do
        nil ->
          body_attrs

        existing ->
          updated_body =
            if is_nil(new_body["refresh_token"]) &&
                 existing.body["refresh_token"] do
              Map.put(new_body, "refresh_token", existing.body["refresh_token"])
            else
              new_body
            end

          Map.put(body_attrs, "body", updated_body)
      end
    end)
  end

  defp extract_scopes_or_default(token) do
    case OauthValidation.extract_scopes(token) do
      {:ok, scopes} -> scopes
      :error -> []
    end
  end

  @doc """
  Normalizes OAuth token expiry time to always use expires_at.

  Converts relative expires_in to absolute expires_at timestamp based on current time.
  If the token already has expires_at, returns it unchanged.

  ## Examples

      iex> normalize_token_expiry(%{"expires_in" => 3600})
      %{"expires_in" => 3600, "expires_at" => 1234567890}

      iex> normalize_token_expiry(%{"expires_at" => 1234567890})
      %{"expires_at" => 1234567890}
  """
  @spec normalize_token_expiry(map()) :: map()
  def normalize_token_expiry(token) when is_map(token) do
    cond do
      Map.has_key?(token, "expires_at") ->
        token

      Map.has_key?(token, "expires_in") ->
        expires_in =
          case token["expires_in"] do
            n when is_integer(n) -> n
            s when is_binary(s) -> String.to_integer(s)
          end

        expires_at =
          DateTime.utc_now()
          |> DateTime.add(expires_in, :second)
          |> DateTime.to_unix()

        Map.put(token, "expires_at", expires_at)

      true ->
        token
    end
  end

  def normalize_token_expiry(token), do: token

  @doc """
  Checks if an OAuth token body is expired or expires soon.

  Returns true if the token expires within the next 5 minutes (300 seconds buffer).
  If expiry cannot be determined, conservatively returns true to trigger refresh.

  ## Examples

      iex> oauth_token_expired?(%{"expires_at" => future_timestamp})
      false

      iex> oauth_token_expired?(%{"expires_at" => soon_timestamp})
      true
  """
  @spec oauth_token_expired?(map()) :: boolean()
  def oauth_token_expired?(body) when is_map(body) do
    case Map.get(body, "expires_at") do
      expires_at when is_integer(expires_at) ->
        current_time = DateTime.utc_now() |> DateTime.to_unix()
        expires_at - current_time < 300

      expires_at when is_binary(expires_at) ->
        case Integer.parse(expires_at) do
          {timestamp, ""} ->
            current_time = DateTime.utc_now() |> DateTime.to_unix()
            timestamp - current_time < 300

          _ ->
            true
        end

      nil ->
        true
    end
  end

  def oauth_token_expired?(_), do: true

  defp handle_oauth_refresh_failed(credential, credential_body, error_response) do
    error_details =
      Map.take(error_response, [:status, :error, :details])
      |> Map.put(:error_type, "reauthorization_required")
      |> Map.put(:client_id, credential.oauth_client_id)
      |> Map.put(:environment, credential_body.name)

    audit_changeset =
      Audit.oauth_token_refresh_failed_event(credential, error_details)

    save_audit_event(audit_changeset)

    {:error, :reauthorization_required}
  end

  @doc """
  Creates a changeset for transferring credentials, validating the provided email.

  ## Parameters

    - `email`: The email address to be included in the changeset.

  ## Returns

    An `Ecto.Changeset` containing the email field.

  ## Example

      iex> credential_transfer_changeset("user@example.com")
      #Ecto.Changeset<...>
  """
  @spec credential_transfer_changeset(String.t()) :: Ecto.Changeset.t()
  def credential_transfer_changeset(email) do
    credential_transfer_changeset()
    |> Ecto.Changeset.cast(%{email: email}, [:email])
  end

  @doc """
  Returns an empty changeset structure for credential transfers with an email field.

  ## Returns

    An `Ecto.Changeset` struct with an empty data map and an email field.

  ## Example

      iex> credential_transfer_changeset()
      #Ecto.Changeset<...>
  """
  @spec credential_transfer_changeset() :: Ecto.Changeset.t()
  def credential_transfer_changeset do
    Ecto.Changeset.cast({%{}, %{email: :string}}, %{}, [:email])
  end

  @doc """
  Validates a credential transfer request.

  This function ensures:
    - The email format is correct.
    - The email does not already exist in the system.
    - The credential is not transferred to the same user.
    - The recipient has access to the necessary projects.

  If the changeset is valid, additional validation checks are applied.

  ## Parameters

    - `changeset`: The `Ecto.Changeset` containing the credential transfer details.
    - `current_user`: The user attempting the credential transfer.
    - `credential`: The credential being transferred.

  ## Returns

    - An updated `Ecto.Changeset` with validation errors if any issues are found.
  """
  @spec validate_credential_transfer(
          Ecto.Changeset.t(),
          Lightning.Accounts.User.t(),
          Lightning.Credentials.Credential.t()
        ) :: Ecto.Changeset.t()
  def validate_credential_transfer(changeset, sender, credential) do
    changeset
    |> Lightning.Accounts.User.validate_email_format()
    |> then(fn changeset ->
      if changeset.valid? do
        changeset
        |> validate_recipient(sender)
        |> validate_project_access(credential)
      else
        changeset
      end
    end)
    |> Map.put(:action, :validate)
  end

  @doc """
  Initiates a credential transfer from the `owner` to the `receiver`.

  This function:
    - Marks the credential as `pending` for transfer.
    - Generates an email token for the credential transfer.
    - Sends a transfer confirmation email to the receiver.

  ## Parameters

    - `owner`: The `User` who currently owns the credential.
    - `receiver`: The `User` who will receive the credential.
    - `credential`: The `Credential` to be transferred.

  ## Returns

    - `:ok` if the transfer process is successfully initiated.
    - `{:error, reason}` if any validation or transaction step fails.

  ## Example

  ```elixir
  case initiate_credential_transfer(owner, receiver, credential) do
    :ok -> IO.puts("Transfer initiated successfully")
    {:error, error} -> IO.inspect(error, label: "Transfer failed")
  end
  ```
  """
  @spec initiate_credential_transfer(User.t(), User.t(), Credential.t()) ::
          :ok | {:error, transfer_error() | Ecto.Changeset.t()}
  def initiate_credential_transfer(
        %User{} = owner,
        %User{} = receiver,
        %Credential{} = credential
      ) do
    {token_value, user_token} =
      UserToken.build_email_token(owner, "credential_transfer", owner.email)

    Multi.new()
    |> Multi.update(:credential, fn _changes ->
      change_credential(credential, %{transfer_status: :pending})
    end)
    |> Multi.insert(:token, user_token)
    |> Repo.transaction()
    |> case do
      {:ok, %{credential: credential, token: _token}} ->
        UserNotifier.deliver_credential_transfer_confirmation_instructions(
          owner,
          receiver,
          credential,
          token_value
        )

        :ok

      {:error, _failed_operation, error, _changes} ->
        {:error, error}
    end
  end

  @doc """
  Confirms and executes a credential transfer.

  This function:
    - Verifies the transfer token to ensure the request is valid.
    - Transfers the credential from the `owner` to the `receiver`.
    - Records the transfer in the audit log.
    - Deletes all related credential transfer tokens.
    - Notifies both parties about the transfer.

  ## Parameters

    - `credential_id`: The ID of the `Credential` being transferred.
    - `receiver_id`: The ID of the `User` receiving the credential.
    - `owner_id`: The ID of the `User` currently owning the credential.
    - `token`: The transfer token for verification.

  ## Returns

    - `{:ok, credential}` on successful transfer.
    - `{:error, reason}` if the transfer fails.

  ## Errors

    - `{:error, :not_found}` if the credential or receiver does not exist.
    - `{:error, :token_error}` if the token is invalid.
    - `{:error, :not_owner}` if the token does not match the credential owner.
    - `{:error, changeset}` if there is a validation or update issue.

  ## Example

  ```elixir
  case confirm_transfer(credential_id, receiver_id, owner_id, token) do
    {:ok, credential} -> IO.puts("Transfer successful")
    {:error, :not_found} -> IO.puts("Error: Credential or receiver not found")
    {:error, :token_error} -> IO.puts("Error: Invalid transfer token")
    {:error, reason} -> IO.inspect(reason, label: "Transfer failed")
  end
  ```
  """
  @spec confirm_transfer(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Credential.t()} | {:error, transfer_error() | Ecto.Changeset.t()}
  def confirm_transfer(credential_id, receiver_id, owner_id, token) do
    with {:ok, owner} <- verify_transfer_token(token, owner_id),
         credential when not is_nil(credential) <- get_credential(credential_id),
         receiver when not is_nil(receiver) <- Accounts.get_user(receiver_id) do
      Multi.new()
      |> Multi.update(:credential, fn _changes ->
        change_credential(credential, %{
          "user_id" => receiver.id,
          "transfer_status" => :completed
        })
      end)
      |> Multi.insert(:audit, fn %{credential: updated_credential} ->
        Audit.user_initiated_event("transfered", credential, %{
          before: %{user_id: credential.user_id},
          after: %{user_id: updated_credential.user_id}
        })
      end)
      |> Multi.delete_all(:tokens, fn _changes ->
        from(t in UserToken,
          where: t.user_id == ^owner.id,
          where: t.context == "credential_transfer"
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{credential: credential} = _result} ->
          UserNotifier.deliver_credential_transfer_notification(
            receiver,
            owner,
            credential
          )

          {:ok, credential}

        {:error, _failed_operation, error, _changes} ->
          {:error, error}
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Revokes a pending credential transfer.

  This function:
    - Ensures the credential exists.
    - Checks that the `owner` is the one who initiated the transfer.
    - Confirms that the credential is still in a `pending` state.
    - Resets the transfer status and deletes related credential transfer tokens.

  ## Parameters

    - `credential_id`: The ID of the `Credential` being revoked.
    - `owner`: The `User` who owns the credential and is revoking the transfer.

  ## Returns

    - `{:ok, credential}` if the transfer is successfully revoked.
    - `{:error, :not_found}` if the credential does not exist.
    - `{:error, :not_owner}` if the user does not own the credential.
    - `{:error, :not_pending}` if the transfer is not in a pending state.
    - `{:error, changeset}` if there is a validation or update issue.

  ## Example

  ```elixir
  case revoke_transfer(credential_id, owner) do
    {:ok, credential} -> IO.puts("Transfer revoked for credential")
    {:error, :not_found} -> IO.puts("Error: Credential not found")
    {:error, :not_owner} -> IO.puts("Error: You do not own this credential")
    {:error, :not_pending} -> IO.puts("Error: Transfer is not pending")
    {:error, reason} -> IO.inspect(reason, label: "Revoke failed")
  end
  ```
  """
  @spec revoke_transfer(String.t(), User.t()) ::
          {:ok, Credential.t()} | {:error, transfer_error() | Ecto.Changeset.t()}
  def revoke_transfer(credential_id, %User{} = owner) do
    with credential when not is_nil(credential) <- get_credential(credential_id),
         true <- credential.user_id == owner.id || :not_owner,
         true <- credential.transfer_status == :pending || :not_pending do
      Multi.new()
      |> Multi.update(:credential, fn _changes ->
        change_credential(credential, %{transfer_status: nil})
      end)
      |> Multi.delete_all(:tokens, fn _changes ->
        from(t in UserToken,
          where: t.user_id == ^owner.id,
          where: t.context == "credential_transfer"
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{credential: credential}} -> {:ok, credential}
        {:error, _op, error, _changes} -> {:error, error}
      end
    else
      nil -> {:error, :not_found}
      :not_owner -> {:error, :not_owner}
      :not_pending -> {:error, :not_pending}
    end
  end

  @spec verify_transfer_token(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, transfer_error()}
  defp verify_transfer_token(token, owner_id) do
    case UserToken.verify_email_token_query(
           token,
           "credential_transfer"
         ) do
      {:ok, query} ->
        case Repo.one(query) do
          nil ->
            {:error, :token_error}

          owner when owner.id == owner_id ->
            {:ok, owner}

          _other ->
            {:error, :not_owner}
        end

      _error ->
        {:error, :token_error}
    end
  end

  @spec validate_project_access(
          Ecto.Changeset.t(),
          Lightning.Credentials.Credential.t()
        ) :: Ecto.Changeset.t()
  defp validate_project_access(changeset, credential) do
    with email when not is_nil(email) <-
           Ecto.Changeset.get_field(changeset, :email),
         user when not is_nil(user) <-
           Lightning.Accounts.get_user_by_email(email),
         projects when projects != [] <-
           projects_blocking_credential_transfer(credential, user) do
      project_names = Enum.map_join(projects, ", ", & &1.name)

      Ecto.Changeset.add_error(
        changeset,
        :email,
        "User doesn't have access to these projects: #{project_names}"
      )
    else
      _ -> changeset
    end
  end

  @spec projects_blocking_credential_transfer(
          Lightning.Credentials.Credential.t(),
          Lightning.Accounts.User.t()
        ) :: [Lightning.Projects.Project.t()]
  defp projects_blocking_credential_transfer(
         %Credential{id: credential_id},
         %User{id: user_id}
       ) do
    from(p in Lightning.Projects.Project,
      join: pc in Lightning.Projects.ProjectCredential,
      on: pc.project_id == p.id and pc.credential_id == ^credential_id,
      left_join: pu in Lightning.Projects.ProjectUser,
      on: pu.project_id == p.id and pu.user_id == ^user_id,
      where: is_nil(pu.id),
      distinct: true,
      select: p
    )
    |> Repo.all()
  end

  defp validate_recipient(changeset, %{email: sender_email} = _sender) do
    recipient_email = Ecto.Changeset.get_field(changeset, :email)

    cond do
      is_nil(recipient_email) ->
        changeset

      recipient_email == sender_email ->
        Ecto.Changeset.add_error(
          changeset,
          :email,
          "You cannot transfer a credential to yourself"
        )

      !Lightning.Repo.exists?(User |> where(email: ^recipient_email)) ->
        Ecto.Changeset.add_error(changeset, :email, "User does not exist")

      true ->
        changeset
    end
  end

  @doc """
  Returns all credentials owned by a specific user that are also being used in a specific project.

  ## Parameters
    - `user`: The `User` struct whose credentials we want to find.
    - `project`: The `Project` struct to check for credential usage.

  ## Returns
    - A list of `Credential` structs that are owned by the user and used in the project.

  ## Examples

      iex> list_user_credentials_in_project(%User{id: 123}, %Project{id: 456})
      [%Credential{user_id: 123, ...}, %Credential{user_id: 123, ...}]
  """
  @spec list_user_credentials_in_project(User.t(), Project.t()) :: [
          Credential.t()
        ]
  def list_user_credentials_in_project(%User{id: user_id}, %Project{
        id: project_id
      }) do
    query =
      from c in Credential,
        join: pc in assoc(c, :project_credentials),
        on: pc.project_id == ^project_id,
        where: c.user_id == ^user_id,
        order_by: [asc: fragment("lower(?)", c.name)],
        distinct: c.id

    Repo.all(query)
  end

  @doc """
  Returns the list of keychain credentials for a project.

  ## Examples

      iex> list_keychain_credentials_for_project(%Project{id: 123})
      [%KeychainCredential{}, ...]

  """
  def list_keychain_credentials_for_project(%Project{id: project_id}) do
    from(kc in KeychainCredential,
      where: kc.project_id == ^project_id,
      order_by: [asc: fragment("lower(?)", kc.name)],
      preload: [:project, :created_by, :default_credential]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single keychain credential.

  Raises `Ecto.NoResultsError` if the KeychainCredential does not exist.

  ## Examples

      iex> get_keychain_credential(123)
      %KeychainCredential{}

      iex> get_keychain_credential(456)
      ** (Ecto.NoResultsError)

  """
  def get_keychain_credential(id), do: Repo.get(KeychainCredential, id)

  @doc """
  Creates a keychain credential.

  ## Examples

      iex> create_keychain_credential(%{name: "My Keychain", path: "$.user_id"})
      {:ok, %KeychainCredential{}}

      iex> create_keychain_credential(%{name: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_keychain_credential(
        %KeychainCredential{} = keychain_credential,
        attrs \\ %{}
      ) do
    keychain_credential
    |> KeychainCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a keychain credential.

  ## Examples

      iex> update_keychain_credential(keychain_credential, %{name: "Updated"})
      {:ok, %KeychainCredential{}}

      iex> update_keychain_credential(keychain_credential, %{name: nil})
      {:error, %Ecto.Changeset{}}

  """
  def update_keychain_credential(
        %KeychainCredential{} = keychain_credential,
        attrs
      ) do
    keychain_credential
    |> KeychainCredential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a keychain credential.

  ## Examples

      iex> delete_keychain_credential(keychain_credential)
      {:ok, %KeychainCredential{}}

      iex> delete_keychain_credential(keychain_credential)
      {:error, %Ecto.Changeset{}}

  """
  def delete_keychain_credential(%KeychainCredential{} = keychain_credential) do
    Repo.delete(keychain_credential)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking keychain credential changes.

  ## Examples

      iex> change_keychain_credential(keychain_credential)
      %Ecto.Changeset{data: %KeychainCredential{}}

  """
  def change_keychain_credential(
        %KeychainCredential{} = keychain_credential,
        attrs \\ %{}
      ) do
    KeychainCredential.changeset(keychain_credential, attrs)
  end

  @doc """
  Creates a new keychain credential struct with proper associations.

  This function ensures that the created_by and project associations are
  properly set and cannot be tampered with via browser params.

  ## Examples

      iex> new_keychain_credential(user, project)
      %KeychainCredential{created_by: user, project: project}

  """
  def new_keychain_credential(
        %Lightning.Accounts.User{} = user,
        %Lightning.Projects.Project{} = project
      ) do
    %KeychainCredential{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:created_by, user)
    |> Ecto.Changeset.put_assoc(:project, project)
    |> Ecto.Changeset.apply_changes()
  end
end
