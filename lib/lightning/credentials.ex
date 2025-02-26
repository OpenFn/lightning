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
    |> Enum.map(&Credential.with_oauth/1)
  end

  @spec list_credentials(User.t()) :: [Credential.t()]
  def list_credentials(%User{id: user_id}) do
    from(c in Credential,
      where: c.user_id == ^user_id,
      preload: [:projects, :user, oauth_token: :oauth_client]
    )
    |> Repo.all()
    |> Enum.map(&Credential.with_oauth/1)
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
  For OAuth credentials, this extracts scopes from the token body, finds or creates
  an OAuth token, and associates it with the credential. OAuth token data is stored
  in the OAuth token body, while credential-specific configuration is stored
  in the credential's body.

  ## Parameters
    * `attrs` - Map of attributes for the credential

  ## Returns
    * `{:ok, credential}` - Successfully created credential
    * `{:error, error}` - Error with creation process
  """
  @spec create_credential(map()) :: {:ok, Credential.t()} | {:error, any()}
  def create_credential(attrs \\ %{}) do
    attrs = normalize_keys(attrs) |> dbg()

    changeset = change_credential(%Credential{}, attrs)

    multi =
      if attrs["schema"] == "oauth" do
        %{"user_id" => user_id, "oauth_client_id" => client_id, "body" => body} =
          attrs

        {credential_data, token_data} = Credentials.separate_oauth_data(body)

        Multi.new()
        |> Multi.run(:oauth_token, fn _repo, _changes ->
          with {:ok, scopes} <- OauthToken.extract_scopes(token_data) do
            OauthToken.find_or_create_for_scopes(
              user_id,
              client_id,
              scopes,
              token_data
            )
          else
            :error -> {:error, "Could not extract scopes from OAuth token"}
          end
        end)
        |> Multi.insert(:credential, fn %{oauth_token: token} ->
          changeset
          |> Ecto.Changeset.put_change(:oauth_token_id, token.id)
          |> Ecto.Changeset.put_change(:body, credential_data)
        end)
      else
        Multi.insert(Multi.new(), :credential, changeset)
      end

    multi
    |> derive_events(changeset)
    |> Repo.transaction()
    |> case do
      {:error, _op, error, _changes} -> {:error, error}
      {:ok, %{credential: credential}} -> {:ok, credential}
    end
  end

  @doc """
  Updates an existing credential.

  For regular credentials, this simply updates the changeset.
  For OAuth credentials with a body update, this updates the associated OAuth token
  with token data and keeps credential-specific configuration
  in the credential's body.

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
    attrs = normalize_keys(attrs) |> dbg()

    changeset =
      credential
      |> change_credential(attrs)
      |> cast_body_change()

    multi =
      if credential.schema == "oauth" && Map.has_key?(attrs, "body") do
        credential = Repo.preload(credential, :oauth_token)
        new_body = attrs["body"]

        {new_credential_data, token_data} =
          Credentials.separate_oauth_data(new_body)

        credential_data = Map.merge(credential.body, new_credential_data)

        Multi.new()
        |> Multi.run(:oauth_token, fn _repo, _changes ->
          if credential.oauth_token_id do
            credential.oauth_token
            |> OauthToken.update_token_changeset(token_data)
            |> Repo.update()
          else
            case OauthToken.extract_scopes(token_data) do
              {:ok, scopes} ->
                oauth_client_id =
                  credential.oauth_client_id || attrs["oauth_client_id"]

                OauthToken.find_or_create_for_scopes(
                  credential.user_id,
                  oauth_client_id,
                  scopes,
                  token_data
                )

              :error ->
                {:error, "Could not extract scopes from OAuth token"}
            end
          end
        end)
        |> Multi.update(:credential, fn %{oauth_token: token} ->
          changeset
          |> Ecto.Changeset.put_change(:body, credential_data)
          |> Ecto.Changeset.put_change(:oauth_token_id, token.id)
        end)
      else
        Multi.update(Multi.new(), :credential, changeset)
      end

    multi
    |> derive_events(changeset)
    |> Repo.transaction()
    |> case do
      {:error, _op, error, _changes} -> {:error, error}
      {:ok, %{credential: credential}} -> {:ok, credential}
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
    date = scheduled_deletion_date()

    changeset =
      Credential.changeset(credential, %{
        "scheduled_deletion" => date
      })

    case Repo.update(changeset) do
      {:ok, updated_credential} ->
        remove_credential_associations(updated_credential)
        maybe_revoke_oauth(updated_credential)
        notify_owner(updated_credential)
        {:ok, updated_credential}

      {:error, changeset} ->
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

  defp maybe_revoke_oauth(%Credential{oauth_client_id: nil}), do: :ok

  defp maybe_revoke_oauth(%Credential{
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
      attrs |> coerce_json_field("body")
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
    %{body: body, oauth_client_id: oauth_client_id, oauth_client: oauth_client} =
      credential =
      credential
      |> preload(oauth_token: :oauth_client)
      |> Credential.with_oauth()

    cond do
      still_fresh(body) ->
        {:ok, credential}

      is_nil(oauth_client_id) ->
        {:ok, credential}

      true ->
        case OauthHTTPClient.refresh_token(oauth_client, body) do
          {:ok, fresh_token} ->
            update_credential(credential, %{body: fresh_token})

          {:error, error} ->
            {:error, error}
        end
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
  @spec still_fresh(map(), integer(), atom()) :: boolean() | {:error, String.t()}
  def still_fresh(token, threshold \\ 5, time_unit \\ :minute)

  def still_fresh(%{"expires_at" => nil} = _token, _threshold, _time_unit),
    do: false

  def still_fresh(%{"expires_in" => nil} = _token, _threshold, _time_unit),
    do: false

  # Handle expires_at case
  def still_fresh(%{"expires_at" => expires_at} = _token, threshold, time_unit)
      when is_integer(expires_at) do
    current_time = DateTime.utc_now()
    expiration_time = DateTime.from_unix!(expires_at)
    time_remaining = DateTime.diff(expiration_time, current_time, time_unit)
    time_remaining >= threshold
  end

  # Handle expires_in with updated_at case
  def still_fresh(
        %{"expires_in" => expires_in, "updated_at" => updated_at} = _token,
        threshold,
        time_unit
      )
      when is_integer(expires_in) and is_struct(updated_at, DateTime) do
    current_time = DateTime.utc_now()
    expiration_time = DateTime.add(updated_at, expires_in, :second)
    time_remaining = DateTime.diff(expiration_time, current_time, time_unit)
    time_remaining >= threshold
  end

  # Fallback for invalid token format
  def still_fresh(_token, _threshold, _time_unit) do
    {:error, "No valid expiration data found"}
  end

  def normalize_keys(map) when is_map(map) do
    if Map.has_key?(map, :__struct__) do
      map
    else
      # Process regular maps
      Enum.reduce(map, %{}, fn
        {k, v}, acc when is_map(v) ->
          Map.put(acc, to_string(k), normalize_keys(v))

        {k, v}, acc ->
          Map.put(acc, to_string(k), v)
      end)
    end
  end

  def normalize_keys(value), do: value

  @doc """
  Gets the list of credential-specific configuration fields.
  These fields stay in the credential body rather than moving to the OAuth token.
  """
  def credential_config_fields do
    ~w(apiVersion)
  end

  @doc """
  Separates credential-specific configuration from OAuth token data.
  Returns a tuple containing {credential_data, token_data}.
  """
  def separate_oauth_data(body) do
    config_fields = credential_config_fields()
    credential_data = Map.take(body, config_fields)
    token_data = Map.drop(body, config_fields)

    {credential_data, token_data}
  end

  @doc """
  Extract OAuth client ID from various possible sources.
  """
  def extract_oauth_client_id(attrs, body) do
    attrs[:oauth_client_id] ||
      Map.get(attrs, "oauth_client_id") ||
      Map.get(body || %{}, "oauth_client_id")
  end

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
      ) do
    # Ensure token_data is a map
    if not is_map(token_data) do
      {:error, "Invalid OAuth token body"}
    else
      normalized_data = normalize_keys(token_data)

      # Access token is always required
      if not Map.has_key?(normalized_data, "access_token") do
        {:error, "Missing required OAuth field: access_token"}
      else
        # For new tokens: refresh_token is required unless there's an existing token with same scopes
        # For updates: refresh_token is not strictly required
        cond do
          # Case 1: This is an update to an existing token (refresh_token not strictly required)
          is_update ->
            validate_expiration_fields(normalized_data)

          # Case 2: No refresh_token but existing token found with same scopes
          not Map.has_key?(normalized_data, "refresh_token") and
            not is_nil(user_id) and not is_nil(oauth_client_id) and
              not is_nil(
                Lightning.Credentials.OauthToken.find_by_scopes(
                  user_id,
                  oauth_client_id,
                  scopes
                )
              ) ->
            validate_expiration_fields(normalized_data)

          # Case 3: New token with no refresh_token and no existing token
          not Map.has_key?(normalized_data, "refresh_token") ->
            {:error, "Missing refresh_token for new OAuth connection"}

          # Case 4: New token with refresh_token (valid case)
          true ->
            validate_expiration_fields(normalized_data)
        end
      end
    end
  end

  # Helper function to validate expiration fields
  defp validate_expiration_fields(token_data) do
    expires_fields = ["expires_in", "expires_at"]

    if not Enum.any?(expires_fields, &Map.has_key?(token_data, &1)) do
      {:error,
       "Missing expiration field: either expires_in or expires_at is required"}
    else
      {:ok, token_data}
    end
  end
end
