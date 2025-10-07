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
      |> handle_transaction_result()
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
    credential_bodies = get_credential_bodies(attrs)

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
      |> handle_transaction_result()
    end
  end

  defp build_update_multi(credential, changeset, credential_bodies) do
    multi = Multi.new() |> Multi.update(:credential, changeset)

    schema_name = Ecto.Changeset.get_field(changeset, :schema)

    delete_environments = Map.get(changeset.params, "delete_environments", [])

    multi =
      if Enum.empty?(delete_environments) do
        multi
      else
        Enum.reduce(delete_environments, multi, fn env_name, acc ->
          acc
          |> Multi.run(:"delete_env_#{env_name}", fn _repo, _changes ->
            case Repo.get_by(CredentialBody,
                   credential_id: credential.id,
                   name: env_name
                 ) do
              nil ->
                {:ok, :not_found}

              credential_body ->
                Repo.delete(credential_body)
                {:ok, :deleted}
            end
          end)
        end)
      end

    if Enum.empty?(credential_bodies) do
      multi
    else
      credential_bodies
      |> Enum.with_index()
      |> Enum.reduce(multi, fn {body_attrs, index}, acc ->
        acc
        |> Multi.run(:"credential_body_#{index}", fn _repo, _changes ->
          upsert_credential_body(credential.id, body_attrs, schema_name)
        end)
      end)
    end
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
    |> coerce_json_field("body")
  end

  # Validation logic for OAuth credentials
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
    with {:ok, _} <- OauthValidation.validate_token_data(body_data),
         :ok <- validate_expected_scopes(body_data, attrs) do
      :ok
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

  defp handle_transaction_result(transaction_result) do
    case transaction_result do
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
  # false positive, it's safe file path (path from config)
  # sobelow_skip ["Traversal.FileModule"]
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
        |> Multi.insert(
          :audit,
          fn %{credential: credential} ->
            Audit.user_initiated_event(
              if(state == :built, do: "created", else: "updated"),
              credential,
              changeset
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
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{credential: credential} ->
        Audit.user_initiated_event("added_to_project", credential, %{
          before: %{project_id: nil},
          after: %{
            project_id: Ecto.Changeset.get_field(changeset, :project_id)
          }
        })
      end
    )
  end

  defp derive_event(multi, %Ecto.Changeset{
         action: :update,
         data: %Lightning.Projects.ProjectCredential{}
       }) do
    multi
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
        # Audit successful revocation
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
        # Audit failed revocation but don't fail the deletion process
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

  # Helper function to save audit events independently
  defp save_audit_event(audit_changeset) do
    case Repo.insert(audit_changeset) do
      {:ok, _audit} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to save audit event: #{inspect(changeset.errors)}")
        # Don't fail the main operation
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
        if is_nil(credential_body.body) do
          []
        else
          SensitiveValues.secret_values(credential_body.body)
        end
    end
  end

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

  defp basic_auth_from_body(body) when is_map(body) do
    usernames = body |> Map.take(["username", "email"]) |> Map.values()
    password = Map.get(body, "password", "")

    usernames
    |> Enum.zip(List.duplicate(password, length(usernames)))
    |> Enum.map(fn {username, password} ->
      Base.encode64("#{username}:#{password}")
    end)
  end

  defp basic_auth_from_body(_), do: []

  @doc """
  Refreshes OAuth tokens in credential bodies if they have expired.

  For OAuth credentials, this checks all credential bodies and refreshes any expired tokens.
  For non-OAuth credentials, returns unchanged.

  ## Parameters
   - `credential`: The `Credential` struct to check and potentially refresh
   - `environment`: Optional environment name to refresh. If nil, refreshes all expired tokens.

  ## Returns
   - `{:ok, credential}`: If tokens were fresh or successfully refreshed
   - `{:error, error}`: If refreshing any token failed
  """
  @spec maybe_refresh_token(Credential.t(), String.t() | nil) ::
          {:ok, Credential.t()} | {:error, oauth_refresh_error() | any()}
  def maybe_refresh_token(credential, environment \\ nil)

  def maybe_refresh_token(%Credential{schema: "oauth"} = credential, environment) do
    credential = Repo.preload(credential, [:credential_bodies, :oauth_client])

    if credential.oauth_client_id do
      refresh_oauth_credential_bodies(credential, environment)
    else
      {:ok, credential}
    end
  end

  def maybe_refresh_token(%Credential{} = credential, _environment) do
    {:ok, credential}
  end

  defp refresh_oauth_credential_bodies(credential, nil) do
    # Refresh all expired tokens
    results =
      credential.credential_bodies
      |> Enum.map(fn credential_body ->
        if oauth_token_expired?(credential_body.body) do
          refresh_credential_body_token(credential, credential_body)
        else
          {:ok, credential_body}
        end
      end)

    # If any failed, return error
    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil -> {:ok, Repo.reload!(credential) |> Repo.preload(:credential_bodies)}
      error -> error
    end
  end

  defp refresh_oauth_credential_bodies(credential, environment) do
    # Refresh specific environment
    credential_body =
      Enum.find(credential.credential_bodies, &(&1.name == environment))

    if credential_body && oauth_token_expired?(credential_body.body) do
      case refresh_credential_body_token(credential, credential_body) do
        {:ok, _} ->
          {:ok, Repo.reload!(credential) |> Repo.preload(:credential_bodies)}

        error ->
          error
      end
    else
      {:ok, credential}
    end
  end

  defp oauth_token_expired?(body) when is_map(body) do
    case body do
      %{"expires_at" => expires_at} when is_integer(expires_at) ->
        current_time = DateTime.utc_now() |> DateTime.to_unix()
        # Refresh if expiring in next 5 minutes
        expires_at - current_time < 300

      %{"expires_in" => _} ->
        # If we only have expires_in without expires_at, assume it needs refresh
        true

      _ ->
        false
    end
  end

  defp oauth_token_expired?(_), do: false

  defp refresh_credential_body_token(credential, credential_body) do
    case OauthHTTPClient.refresh_token(
           credential.oauth_client,
           credential_body.body
         ) do
      {:ok, fresh_token} ->
        # Extract scopes from fresh token
        {:ok, scopes} = OauthValidation.extract_scopes(fresh_token)

        refresh_metadata = %{
          client_id: credential.oauth_client_id,
          environment: credential_body.name,
          scopes: scopes,
          expires_in: Map.get(fresh_token, "expires_in"),
          token_type: Map.get(fresh_token, "token_type", "Bearer")
        }

        audit_changeset =
          Audit.oauth_token_refreshed_event(credential, refresh_metadata)

        # Preserve refresh_token if not in new response
        updated_token =
          ensure_refresh_token_preserved(credential_body.body, fresh_token)

        case CredentialBody.changeset(credential_body, %{body: updated_token})
             |> Repo.update() do
          {:ok, updated_cb} ->
            save_audit_event(audit_changeset)
            {:ok, updated_cb}

          error ->
            error
        end

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

  defp ensure_refresh_token_preserved(existing_body, new_body)
       when is_map(existing_body) and is_map(new_body) do
    case {existing_body["refresh_token"], new_body["refresh_token"]} do
      {existing, nil} when existing != nil ->
        Map.put(new_body, "refresh_token", existing)

      _ ->
        new_body
    end
  end

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
