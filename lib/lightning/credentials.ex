defmodule Lightning.Credentials do
  @moduledoc """
  The Credentials context.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]

  alias Ecto.Multi
  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserNotifier
  alias Lightning.Accounts.UserToken
  alias Lightning.AuthProviders.Common
  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.Credentials
  alias Lightning.Credentials.Audit
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthToken
  alias Lightning.Credentials.SchemaDocument
  alias Lightning.Credentials.SensitiveValues
  alias Lightning.Projects.Project
  alias Lightning.Repo

  require Logger

  @type transfer_error :: :token_error | :not_found | :not_owner

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
          {:ok, updated_credential} <- [
            update_credential(credential, %{body: %{}})
          ],
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
    Ecto.assoc(project, :credentials)
    |> preload([
      :user,
      :project_credentials,
      :projects,
      oauth_token: :oauth_client
    ])
    |> Repo.all()
  end

  @spec list_credentials(User.t()) :: [Credential.t()]
  def list_credentials(%User{id: user_id}) do
    from(c in Credential,
      where: c.user_id == ^user_id,
      preload: [:projects, :user, oauth_token: :oauth_client]
    )
    |> Repo.all()
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

  def get_credential_for_update!(id) do
    Credential
    |> Repo.get!(id)
    |> Repo.preload([:project_credentials, :projects])
  end

  @doc """
  Creates a new credential.

  For regular credentials, this simply inserts the changeset.
  For OAuth credentials, this uses the oauth_token data provided directly,
  finds or creates an OAuth token, and associates it with the credential.

  ## Parameters
    * `attrs` - Map of attributes for the credential including:
      * `user_id` - User ID
      * `schema` - Schema type ("oauth" for OAuth credentials)
      * `oauth_client_id` - OAuth client ID (for OAuth credentials)
      * `body` - Credential configuration data
      * `oauth_token` - OAuth token data (for OAuth credentials)

  ## Returns
    * `{:ok, credential}` - Successfully created credential
    * `{:error, error}` - Error with creation process
  """
  @spec create_credential(map()) :: {:ok, Credential.t()} | {:error, any()}
  def create_credential(attrs \\ %{}) do
    attrs = normalize_keys(attrs)
    changeset = change_credential(%Credential{}, attrs)

    build_create_multi(changeset, attrs)
    |> derive_events(changeset)
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  defp build_create_multi(changeset, attrs) do
    if oauth_credential?(attrs) do
      build_oauth_create_multi(changeset, attrs)
    else
      Multi.insert(Multi.new(), :credential, changeset)
    end
  end

  defp oauth_credential?(attrs), do: attrs["schema"] == "oauth"

  defp build_oauth_create_multi(changeset, %{
         "user_id" => user_id,
         "oauth_client_id" => client_id,
         "body" => body,
         "oauth_token" => token
       }) do
    base_multi =
      Multi.new()
      |> Multi.run(:scopes, fn _repo, _changes ->
        case OauthToken.extract_scopes(token) do
          {:ok, scopes} -> {:ok, scopes}
          :error -> {:error, "Missing required OAuth field: scope"}
        end
      end)

    token_multi = build_token_multi(user_id, client_id, token)

    base_multi
    |> Multi.append(token_multi)
    |> Multi.insert(:credential, fn %{oauth_token: fresh_token} ->
      changeset
      |> Ecto.Changeset.put_change(:oauth_token_id, fresh_token.id)
      |> Ecto.Changeset.put_change(:body, body)
    end)
  end

  defp build_token_multi(user_id, client_id, token) do
    if token["refresh_token"] do
      Multi.new()
      |> Multi.insert(:oauth_token, fn %{scopes: scopes} ->
        OauthToken.changeset(%{
          user_id: user_id,
          oauth_client_id: client_id,
          scopes: scopes,
          body: token
        })
      end)
    else
      Multi.new()
      |> Multi.run(:token_changeset, fn _repo, %{scopes: scopes} ->
        handle_missing_refresh_token(user_id, client_id, scopes, token)
      end)
      |> Multi.insert(:oauth_token, fn %{token_changeset: token_changeset} ->
        token_changeset
      end)
    end
  end

  defp handle_missing_refresh_token(user_id, client_id, scopes, token) do
    case find_oauth_token_by_scopes(user_id, client_id, scopes) do
      nil ->
        return_error("Missing required OAuth field: refresh_token")

      oauth_token ->
        refresh_token = oauth_token.body["refresh_token"]
        updated_token = Map.put(token, "refresh_token", refresh_token)

        {:ok,
         OauthToken.changeset(%{
           user_id: user_id,
           oauth_client_id: client_id,
           scopes: scopes,
           body: updated_token
         })}
    end
  end

  @doc """
  Updates an existing credential.

  For regular credentials, this simply updates the changeset.
  For OAuth credentials, this updates the associated OAuth token
  with token data provided in the oauth_token parameter.

  ## Parameters
    * `credential` - The credential to update
    * `attrs` - Map of attributes to update

  ## Returns
    * `{:ok, credential}` - Successfully updated credential
    * `{:error, error}` - Error with update process
  """
  @spec update_credential(Credential.t(), map()) ::
          {:ok, Credential.t()} | {:error, any()}
  def update_credential(%Credential{} = credential, attrs) do
    attrs = normalize_keys(attrs)
    changeset = change_credential(credential, attrs)

    build_update_multi(credential, changeset, attrs)
    |> derive_events(changeset)
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  defp build_update_multi(credential, changeset, attrs) do
    if should_update_oauth?(credential, attrs) do
      build_oauth_update_multi(credential, changeset, attrs)
    else
      Multi.update(Multi.new(), :credential, changeset)
    end
  end

  defp should_update_oauth?(credential, attrs) do
    credential.schema == "oauth" && Map.has_key?(attrs, "oauth_token")
  end

  defp build_oauth_update_multi(credential, changeset, attrs) do
    credential = Repo.preload(credential, :oauth_token)
    credential_data = Map.get(attrs, "body", credential.body)

    Multi.new()
    |> Multi.run(:oauth_token, fn _repo, _changes ->
      credential.oauth_token
      |> OauthToken.update_token_changeset(attrs["oauth_token"])
      |> Repo.update()
    end)
    |> Multi.update(:credential, fn %{oauth_token: token} ->
      changeset
      |> Ecto.Changeset.put_change(:body, credential_data)
      |> Ecto.Changeset.put_change(:oauth_token_id, token.id)
    end)
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
           oauth_token: :oauth_client
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

  defp cast_body_change(
         %Ecto.Changeset{valid?: true, changes: %{body: body}} = changeset
       ) do
    schema_name = Ecto.Changeset.get_field(changeset, :schema)

    case put_typed_body(body, schema_name) do
      {:ok, updated_body} ->
        Ecto.Changeset.put_change(changeset, :body, updated_body)

      {:error, _reason} ->
        Ecto.Changeset.add_error(changeset, :body, "Invalid body types")
    end
  end

  defp cast_body_change(changeset), do: changeset

  defp put_typed_body(body, schema_name)
       when schema_name in ["raw", "salesforce_oauth", "googlesheets", "oauth"],
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
      {:ok, repo.preload(cred, [:oauth_token])}
    end)
    |> Multi.run(:associations, fn _repo, %{preloaded: cred} ->
      remove_credential_associations(cred)
      {:ok, cred}
    end)
    |> Multi.run(:revoke_oauth, fn _repo, %{preloaded: cred} ->
      maybe_revoke_oauth(cred.oauth_token)
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

  defp maybe_revoke_oauth(nil), do: :ok
  defp maybe_revoke_oauth(%OauthToken{oauth_client_id: nil}), do: :ok

  defp maybe_revoke_oauth(%OauthToken{
         oauth_client_id: oauth_client_id,
         body: body
       }) do
    client = Repo.get(OauthClient, oauth_client_id)

    if client.revocation_endpoint do
      OauthHTTPClient.revoke_token(client, body)
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
    Credential.changeset(
      credential,
      attrs |> normalize_keys() |> coerce_json_field("body")
    )
    |> cast_body_change()
  end

  @spec sensitive_values_for(Ecto.UUID.t() | Credential.t() | nil) :: [any()]
  def sensitive_values_for(id) when is_binary(id) do
    sensitive_values_for(get_credential!(id))
  end

  def sensitive_values_for(nil), do: []

  def sensitive_values_for(%Credential{body: body}) do
    if is_nil(body) do
      []
    else
      SensitiveValues.secret_values(body)
    end
  end

  def basic_auth_for(%Credential{body: body}) when is_map(body) do
    usernames =
      body
      |> Map.take(["username", "email"])
      |> Map.values()

    password = Map.get(body, "password", "")

    usernames
    |> Enum.zip(List.duplicate(password, length(usernames)))
    |> Enum.map(fn {username, password} ->
      Base.encode64("#{username}:#{password}")
    end)
  end

  def basic_auth_for(_credential), do: []

  def maybe_refresh_token(%Credential{schema: "oauth"} = credential) do
    credential =
      %{oauth_token: oauth_token} =
      Repo.preload(credential, oauth_token: :oauth_client)

    cond do
      still_fresh(oauth_token) ->
        {:ok, credential}

      is_nil(oauth_token.oauth_client_id) ->
        {:ok, credential}

      true ->
        case OauthHTTPClient.refresh_token(
               oauth_token.oauth_client,
               oauth_token.body
             ) do
          {:ok, fresh_token} ->
            update_credential(credential, %{oauth_token: fresh_token})

          {:error, error} ->
            {:error, error}
        end
    end
  end

  # TODO: Remove this function when deprecating salesforce and googlesheets oauth
  def maybe_refresh_token(%Credential{schema: schema} = credential)
      when schema in ["salesforce_oauth", "googlesheets"] do
    token = Common.TokenBody.new(credential.body)

    if Common.still_fresh(token) do
      {:ok, credential}
    else
      adapter = lookup_adapter(schema)
      wellknown_url = adapter.wellknown_url(token.sandbox)

      case adapter.refresh_token(token, wellknown_url) do
        {:ok, refreshed_token} ->
          updated_body =
            refreshed_token
            |> Common.TokenBody.from_oauth2_token()
            |> Lightning.Helpers.json_safe()

          update_credential(credential, %{body: updated_body})

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def maybe_refresh_token(%Credential{} = credential) do
    {:ok, credential}
  end

  # TODO: Remove this function when deprecating salesforce and googlesheets oauth
  def lookup_adapter(schema) do
    case :ets.lookup(:adapter_lookup, schema) do
      [{^schema, adapter}] -> adapter
      [] -> nil
    end
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
  Determines if the token data is still considered fresh.

  ## Parameters
  - `token`: a map containing token data with `expires_at` or `expires_in` fields.
    When using `expires_in`, the function will use the token's `updated_at` timestamp.
  - `threshold`: the number of time units before expiration to consider the token still fresh.
  - `time_unit`: the unit of time to consider for the threshold comparison.

  ## Returns
  - `true` if the token is fresh.
  - `false` if the token is not fresh.
  - `{:error, reason}` if the token's expiration data is missing or invalid.
  """
  @spec still_fresh(OauthToken.t(), integer(), atom()) ::
          boolean() | {:error, String.t()}
  def still_fresh(token, threshold \\ 5, time_unit \\ :minute)

  def still_fresh(
        %OauthToken{body: %{"expires_at" => nil}} = _token,
        _threshold,
        _time_unit
      ),
      do: false

  def still_fresh(
        %OauthToken{body: %{"expires_in" => nil}} = _token,
        _threshold,
        _time_unit
      ),
      do: false

  def still_fresh(
        %OauthToken{body: %{"expires_at" => expires_at}} = _token,
        threshold,
        time_unit
      )
      when is_integer(expires_at) do
    expires_at
    |> DateTime.from_unix!()
    |> DateTime.diff(DateTime.utc_now(), time_unit) >= threshold
  end

  def still_fresh(
        %OauthToken{body: %{"expires_in" => expires_in}, updated_at: updated_at} =
          _token,
        threshold,
        time_unit
      )
      when is_integer(expires_in) do
    updated_at
    |> DateTime.add(expires_in, :second)
    |> DateTime.diff(DateTime.utc_now(), time_unit) >= threshold
  end

  def still_fresh(_token, _threshold, _time_unit) do
    {:error, "No valid expiration data found"}
  end

  def normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_map(v) ->
        Map.put(acc, to_string(k), normalize_keys(v))

      {k, v}, acc ->
        Map.put(acc, to_string(k), v)
    end)
  end

  def normalize_keys(value), do: value

  @doc """
  Validates OAuth token data according to OAuth standards.
  This function is used by both OauthToken and Credential modules to ensure
  consistent validation of OAuth tokens.

  ## Parameters
    * `token_data` - The OAuth token data to validate
    * `user_id` - User ID associated with the token
    * `oauth_client_id` - OAuth client ID
    * `scopes` - List of scopes for the token
    * `is_update` - Whether this is an update to an existing token

  ## Returns
    * `{:ok, token_data}` - Token data is valid
    * `{:error, reason}` - Token data is invalid with reason
  """
  def validate_oauth_token_data(
        token_data,
        user_id,
        oauth_client_id,
        scopes,
        is_update \\ false
      )

  def validate_oauth_token_data(
        token_data,
        _user_id,
        _oauth_client_id,
        _scopes,
        _is_update
      )
      when not is_map(token_data) do
    return_error("Invalid OAuth token body")
  end

  def validate_oauth_token_data(
        _token_data,
        _user_id,
        _oauth_client_id,
        scopes,
        _is_update
      )
      when is_nil(scopes) do
    return_error("Missing required OAuth field: scope")
  end

  def validate_oauth_token_data(
        token_data,
        user_id,
        oauth_client_id,
        scopes,
        is_update
      ) do
    normalized_data = normalize_keys(token_data)

    validate_with_access_token(
      normalized_data,
      user_id,
      oauth_client_id,
      scopes,
      is_update
    )
  end

  defp validate_with_access_token(
         %{"access_token" => _} = normalized_data,
         user_id,
         oauth_client_id,
         scopes,
         is_update
       ) do
    validate_refresh_token_and_expiration(
      normalized_data,
      user_id,
      oauth_client_id,
      scopes,
      is_update
    )
  end

  defp validate_with_access_token(
         _,
         _user_id,
         _oauth_client_id,
         _scopes,
         _is_update
       ) do
    return_error("Missing required OAuth field: access_token")
  end

  defp return_error(message), do: {:error, message}

  defp validate_refresh_token_and_expiration(
         normalized_data,
         user_id,
         oauth_client_id,
         scopes,
         is_update
       ) do
    has_refresh_token? = Map.has_key?(normalized_data, "refresh_token")

    existing_token_exists? =
      token_exists?(user_id, oauth_client_id, scopes)

    cond do
      is_update ->
        validate_expiration_fields(normalized_data)

      existing_token_exists? ->
        validate_expiration_fields(normalized_data)

      has_refresh_token? ->
        validate_expiration_fields(normalized_data)

      true ->
        return_error("Missing refresh_token for new OAuth connection")
    end
  end

  defp token_exists?(nil, _, _), do: false
  defp token_exists?(_, nil, _), do: false
  defp token_exists?(_, _, nil), do: false

  defp token_exists?(user_id, oauth_client_id, scopes) do
    find_oauth_token_by_scopes(
      user_id,
      oauth_client_id,
      scopes
    ) != nil
  end

  defp validate_expiration_fields(token_data) do
    if has_expiration_field?(token_data) do
      {:ok, token_data}
    else
      return_error(
        "Missing expiration field: either expires_in or expires_at is required"
      )
    end
  end

  defp has_expiration_field?(token_data) do
    expires_fields = ["expires_in", "expires_at"]
    Enum.any?(expires_fields, &Map.has_key?(token_data, &1))
  end

  defp find_oauth_token_by_scopes(user_id, oauth_client_id, scopes)
       when is_list(scopes) do
    incoming_scopes = MapSet.new(scopes)
    incoming_size = MapSet.size(incoming_scopes)

    Ecto.Query.from(t in OauthToken,
      join: token_client in OauthClient,
      on: t.oauth_client_id == token_client.id,
      join: reference_client in OauthClient,
      on: reference_client.id == ^oauth_client_id,
      where:
        t.user_id == ^user_id and
          token_client.client_id == reference_client.client_id and
          token_client.client_secret == reference_client.client_secret
    )
    |> Lightning.Repo.all()
    |> Enum.filter(fn token ->
      existing_scopes = MapSet.new(token.scopes)
      MapSet.intersection(existing_scopes, incoming_scopes) |> MapSet.size() > 0
    end)
    |> Enum.max_by(
      fn token ->
        existing_scopes = MapSet.new(token.scopes)

        common_count =
          MapSet.intersection(existing_scopes, incoming_scopes) |> MapSet.size()

        extra_count =
          MapSet.difference(existing_scopes, incoming_scopes) |> MapSet.size()

        exact_match? = common_count == incoming_size && extra_count == 0
        timestamp = DateTime.to_unix(token.updated_at)

        {if(exact_match?, do: 1, else: 0), common_count, -extra_count, timestamp}
      end,
      fn -> nil end
    )
  end
end
