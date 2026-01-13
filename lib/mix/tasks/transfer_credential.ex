defmodule Mix.Tasks.Lightning.TransferCredential do
  @shortdoc "Transfer credential ownership between users"
  @moduledoc """
  Transfer credential ownership between users.

  ## Modes

  This task supports several modes of operation:

  ### Transfer Mode (default)

  Transfer a single credential:

      mix lightning.transfer_credential --name "My Credential" --from user@example.com --to new@example.com
      mix lightning.transfer_credential --id <UUID> --to new@example.com

  ### List Mode

  List credentials for a user:

      mix lightning.transfer_credential --list --from user@example.com
      mix lightning.transfer_credential --list --from-user-id <UUID> --project <UUID>

  ### Bulk Transfer Mode

  Transfer all credentials from one user to another:

      mix lightning.transfer_credential --all --from old@example.com --to new@example.com

  ### Undo Mode

  Reverse a previous transfer using its audit ID:

      mix lightning.transfer_credential --undo <AUDIT_ID>

  ## Options

  ### Credential Selection

    * `-n, --name NAME` - Name of the credential to transfer
    * `-i, --id UUID` - ID of the credential to transfer
    * `--all` - Transfer all credentials from source user

  ### User Selection

    * `-f, --from EMAIL` - Email of the current owner
    * `--from-user-id UUID` - ID of the current owner
    * `-t, --to EMAIL` - Email of the new owner
    * `--to-user-id UUID` - ID of the new owner

  ### Filtering

    * `-p, --project UUID` - Filter by project
    * `-s, --schema NAME` - Filter by credential schema (e.g., "salesforce", "dhis2")

  ### Output

    * `--format FORMAT` - Output format: table (default), json, quiet
    * `--list` - List credentials instead of transferring

  ### Transfer Options

    * `-r, --rename NAME` - Rename credential during transfer
    * `--rename-on-conflict` - Auto-rename conflicting credentials in bulk mode
      (appends " (from source@email.com)" to the name)
    * `--reason TEXT` - Reason for transfer (stored in audit log)
    * `--dry-run` - Show what would happen without making changes
    * `--undo AUDIT_ID` - Reverse a previous transfer

  ## Exit Codes

    * 0 - Success
    * 1 - General error (not found, validation failed)
    * 2 - Conflict (name collision)

  ## Examples

      # Transfer by name
      mix lightning.transfer_credential -n "SF OAuth" -f old@example.com -t new@example.com

      # Transfer by ID (shortest form)
      mix lightning.transfer_credential -i abc123 -t new@example.com

      # List credentials for a user
      mix lightning.transfer_credential --list -f user@example.com

      # List with filters
      mix lightning.transfer_credential --list -f user@example.com -p <PROJECT_UUID> -s salesforce

      # Transfer all credentials
      mix lightning.transfer_credential --all -f old@example.com -t new@example.com --dry-run

      # Transfer all, auto-renaming on conflict
      mix lightning.transfer_credential --all -f old@example.com -t new@example.com --rename-on-conflict

      # JSON output for scripting
      mix lightning.transfer_credential -i <UUID> -t new@example.com --format json

      # Undo a transfer
      mix lightning.transfer_credential --undo <AUDIT_ID>
  """

  use Mix.Task

  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Audit, as: CredentialAudit
  alias Lightning.Credentials.Credential
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo

  @exit_success 0
  @exit_error 1
  @exit_conflict 2
  # Used in bulk mode when some transfers succeed but others fail
  @exit_partial 3

  @valid_formats ~w(table json quiet)

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [
          name: :string,
          id: :string,
          all: :boolean,
          from: :string,
          from_user_id: :string,
          to: :string,
          to_user_id: :string,
          project: :string,
          schema: :string,
          format: :string,
          list: :boolean,
          rename: :string,
          rename_on_conflict: :boolean,
          reason: :string,
          dry_run: :boolean,
          undo: :string
        ],
        aliases: [
          n: :name,
          i: :id,
          f: :from,
          t: :to,
          p: :project,
          s: :schema,
          r: :rename
        ]
      )

    with :ok <- validate_no_positional(positional),
         :ok <- validate_no_invalid(invalid),
         :ok <- validate_format(opts),
         :ok <- validate_uuids(opts) do
      Mix.Task.run("app.start")

      detect_mode(opts) |> execute(opts)
    end
  end

  defp validate_no_positional([]), do: :ok

  defp validate_no_positional(positional) do
    Mix.raise("""
    Unexpected positional arguments: #{inspect(positional)}

    Use --name "Name" instead of passing the name as an argument.
    Run `mix help lightning.transfer_credential` for usage.
    """)
  end

  defp validate_no_invalid([]), do: :ok

  defp validate_no_invalid(invalid) do
    invalid_opts = Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)

    Mix.raise("""
    Unknown option(s): #{invalid_opts}

    Run `mix help lightning.transfer_credential` for usage.
    """)
  end

  defp validate_format(opts) do
    case Keyword.get(opts, :format, "table") do
      format when format in @valid_formats ->
        :ok

      invalid ->
        Mix.raise(
          "Invalid format: #{invalid}. Valid formats: #{Enum.join(@valid_formats, ", ")}"
        )
    end
  end

  defp validate_uuids(opts) do
    uuid_opts = [:id, :from_user_id, :to_user_id, :project, :undo]

    invalid =
      Enum.filter(uuid_opts, fn key ->
        case Keyword.get(opts, key) do
          nil -> false
          value -> not valid_uuid?(value)
        end
      end)

    if Enum.empty?(invalid) do
      :ok
    else
      invalid_str = Enum.map_join(invalid, ", ", &"--#{format_opt_name(&1)}")
      Mix.raise("Invalid UUID format for: #{invalid_str}")
    end
  end

  defp valid_uuid?(string) do
    case Ecto.UUID.cast(string) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp format_opt_name(atom) do
    atom |> Atom.to_string() |> String.replace("_", "-")
  end

  defp detect_mode(opts) do
    cond do
      Keyword.has_key?(opts, :undo) -> :undo
      Keyword.has_key?(opts, :list) -> :list
      Keyword.has_key?(opts, :all) -> :bulk
      true -> :single
    end
  end

  defp execute(:undo, opts), do: execute_undo(opts)
  defp execute(:list, opts), do: execute_list(opts)
  defp execute(:bulk, opts), do: execute_bulk(opts)
  defp execute(:single, opts), do: execute_single(opts)

  defp execute_single(opts) do
    format = Keyword.get(opts, :format, "table")
    dry_run = Keyword.get(opts, :dry_run, false)
    rename = Keyword.get(opts, :rename)
    reason = Keyword.get(opts, :reason)

    with {:ok, credential, source_user} <- find_credential(opts),
         {:ok, target_user} <- find_target_user(opts),
         :ok <- validate_different_users(source_user, target_user) do
      final_name = rename || credential.name

      transfer = %{
        credential: credential,
        source_user: source_user,
        target_user: target_user,
        final_name: final_name,
        reason: reason
      }

      if dry_run do
        output_transfer_plan([transfer], format, dry_run: true)
        exit_with(@exit_success)
      else
        case perform_transfer(transfer) do
          {:ok, result} ->
            output_transfer_result([result], format)
            exit_with(@exit_success)

          {:error, {:conflict, message}} ->
            output_error(message, format)
            exit_with(@exit_conflict)

          {:error, reason} ->
            output_error(reason, format)
            exit_with(@exit_error)
        end
      end
    else
      {:error, message} ->
        output_error(message, format)
        exit_with(@exit_error)
    end
  end

  defp execute_list(opts) do
    format = Keyword.get(opts, :format, "table")

    case find_source_user(opts) do
      {:ok, user} ->
        credentials = list_credentials(user, opts)
        output_credential_list(credentials, user, format)
        exit_with(@exit_success)

      {:error, message} ->
        output_error(message, format)
        exit_with(@exit_error)
    end
  end

  defp list_credentials(user, opts) do
    from(c in Credential,
      where: c.user_id == ^user.id,
      order_by: [asc: c.name]
    )
    |> filter_by_project(Keyword.get(opts, :project))
    |> filter_by_schema(Keyword.get(opts, :schema))
    |> Repo.all()
    |> Repo.preload(:projects)
  end

  defp filter_by_project(query, nil), do: query

  defp filter_by_project(query, project_id) do
    from(c in query,
      join: pc in ProjectCredential,
      on: pc.credential_id == c.id,
      where: pc.project_id == ^project_id
    )
  end

  defp filter_by_schema(query, nil), do: query

  defp filter_by_schema(query, schema),
    do: from(c in query, where: c.schema == ^schema)

  defp execute_bulk(opts) do
    format = Keyword.get(opts, :format, "table")
    dry_run = Keyword.get(opts, :dry_run, false)
    reason = Keyword.get(opts, :reason)
    rename_on_conflict = Keyword.get(opts, :rename_on_conflict, false)

    with {:ok, source_user} <- find_source_user(opts),
         {:ok, target_user} <- find_target_user(opts),
         :ok <- validate_different_users(source_user, target_user) do
      credentials = list_credentials(source_user, opts)

      cond do
        Enum.empty?(credentials) ->
          output_message("No credentials found for #{source_user.email}", format)
          exit_with(@exit_success)

        dry_run ->
          transfers =
            build_transfers(credentials, source_user, target_user, reason)

          output_transfer_plan(transfers, format, dry_run: true)
          exit_with(@exit_success)

        true ->
          transfers =
            build_transfers(credentials, source_user, target_user, reason)

          {successes, conflicts, errors} =
            execute_bulk_transfers(transfers, source_user, rename_on_conflict)

          handle_bulk_results(successes, conflicts, errors, target_user, format)
      end
    else
      {:error, message} ->
        output_error(message, format)
        exit_with(@exit_error)
    end
  end

  defp build_transfers(credentials, source_user, target_user, reason) do
    Enum.map(credentials, fn cred ->
      build_transfer(cred, source_user, target_user, cred.name, reason)
    end)
  end

  defp handle_bulk_results(successes, conflicts, errors, target_user, format) do
    unless Enum.empty?(successes), do: output_transfer_result(successes, format)

    unless Enum.empty?(conflicts),
      do: output_conflicts(conflicts, target_user, format)

    cond do
      Enum.empty?(successes) and not Enum.empty?(conflicts) ->
        output_error(
          "All credentials have naming conflicts. Use --rename-on-conflict or transfer individually.",
          format
        )

        exit_with(@exit_conflict)

      not Enum.empty?(errors) ->
        output_message("\n#{length(errors)} transfer(s) failed.", format)
        exit_with(@exit_partial)

      not Enum.empty?(conflicts) ->
        exit_with(@exit_partial)

      true ->
        exit_with(@exit_success)
    end
  end

  defp execute_bulk_transfers(transfers, source_user, rename_on_conflict) do
    Enum.reduce(transfers, {[], [], []}, fn transfer,
                                            {successes, conflicts, errors} ->
      case perform_transfer(transfer) do
        {:ok, result} ->
          {[result | successes], conflicts, errors}

        {:error, {:conflict, _message}} ->
          handle_conflict(
            transfer,
            source_user,
            rename_on_conflict,
            successes,
            conflicts,
            errors
          )

        {:error, reason} ->
          {successes, conflicts, [reason | errors]}
      end
    end)
    |> then(fn {s, c, e} ->
      {Enum.reverse(s), Enum.reverse(c), Enum.reverse(e)}
    end)
  end

  defp handle_conflict(
         transfer,
         source_user,
         true = _rename_on_conflict,
         successes,
         conflicts,
         errors
       ) do
    renamed_transfer = %{
      transfer
      | final_name: "#{transfer.credential.name} (from #{source_user.email})"
    }

    case perform_transfer(renamed_transfer) do
      {:ok, result} ->
        {[result | successes], conflicts, errors}

      {:error, {:conflict, _}} ->
        {successes, [transfer.credential | conflicts], errors}

      {:error, reason} ->
        {successes, conflicts, [reason | errors]}
    end
  end

  defp handle_conflict(
         transfer,
         _source_user,
         false = _rename_on_conflict,
         successes,
         conflicts,
         errors
       ) do
    {successes, [transfer.credential | conflicts], errors}
  end

  defp execute_undo(opts) do
    format = Keyword.get(opts, :format, "table")
    dry_run = Keyword.get(opts, :dry_run, false)
    audit_id = Keyword.fetch!(opts, :undo)

    with {:ok, audit_event} <- find_transfer_audit(audit_id),
         {:ok, credential} <- find_credential_for_undo(audit_event),
         {:ok, original_owner} <- find_original_owner(audit_event) do
      current_owner = Repo.preload(credential, :user).user

      transfer = %{
        credential: credential,
        source_user: current_owner,
        target_user: original_owner,
        final_name: credential.name,
        reason: "Undo transfer #{audit_id}"
      }

      if dry_run do
        output_message("Would undo transfer:", format)
        output_transfer_plan([transfer], format, dry_run: true)
        exit_with(@exit_success)
      else
        case perform_transfer(transfer) do
          {:ok, result} ->
            output_message("Transfer undone successfully:", format)
            output_transfer_result([result], format)
            exit_with(@exit_success)

          {:error, {:conflict, message}} ->
            output_error(message, format)
            exit_with(@exit_conflict)

          {:error, reason} ->
            output_error(reason, format)
            exit_with(@exit_error)
        end
      end
    else
      {:error, message} ->
        output_error(message, format)
        exit_with(@exit_error)
    end
  end

  defp find_transfer_audit(audit_id) do
    query =
      from(a in Lightning.Auditing.Audit,
        where:
          a.id == ^audit_id and a.item_type == "credential" and
            a.event == "transferred"
      )

    case Repo.one(query) do
      nil -> {:error, "Transfer audit event not found: #{audit_id}"}
      audit -> {:ok, audit}
    end
  end

  defp find_credential_for_undo(audit_event) do
    case Repo.get(Credential, audit_event.item_id) do
      nil -> {:error, "Credential no longer exists: #{audit_event.item_id}"}
      credential -> {:ok, credential}
    end
  end

  defp find_original_owner(audit_event) do
    # The original owner is stored in audit metadata. Falls back to actor_id
    # for transfers done via the web UI (which doesn't store from_user_id).
    original_user_id =
      get_in(audit_event.metadata, ["from_user_id"]) || audit_event.actor_id

    case Repo.get(User, original_user_id) do
      nil -> {:error, "Original owner no longer exists"}
      user -> {:ok, user}
    end
  end

  defp find_credential(opts) do
    do_find_credential(
      Keyword.get(opts, :id),
      Keyword.get(opts, :name),
      opts
    )
  end

  defp do_find_credential(id, _name, _opts) when is_binary(id) do
    case Repo.get(Credential, id) |> Repo.preload(:user) do
      nil -> {:error, "Credential not found: #{id}"}
      cred -> {:ok, cred, cred.user}
    end
  end

  defp do_find_credential(nil, name, opts) when is_binary(name) do
    with {:ok, source_user} <- find_source_user(opts) do
      find_credential_by_name(name, source_user, Keyword.get(opts, :project))
    end
  end

  defp do_find_credential(nil, nil, _opts) do
    {:error, "Missing credential. Use --id UUID or --name NAME (with --from)"}
  end

  defp find_credential_by_name(name, owner, nil) do
    case Repo.one(
           from(c in Credential,
             where: c.user_id == ^owner.id and c.name == ^name
           )
         ) do
      nil -> {:error, "Credential '#{name}' not found for #{owner.email}"}
      cred -> {:ok, cred, owner}
    end
  end

  defp find_credential_by_name(name, owner, project_id) do
    query =
      from(c in Credential,
        join: pc in ProjectCredential,
        on: pc.credential_id == c.id,
        where:
          pc.project_id == ^project_id and c.user_id == ^owner.id and
            c.name == ^name
      )

    case Repo.one(query) do
      nil ->
        {:error,
         "Credential '#{name}' not found for #{owner.email} in project #{project_id}"}

      cred ->
        {:ok, cred, owner}
    end
  end

  defp find_source_user(opts) do
    find_user(
      Keyword.get(opts, :from_user_id),
      Keyword.get(opts, :from),
      "source user",
      "--from EMAIL or --from-user-id UUID"
    )
  end

  defp find_target_user(opts) do
    find_user(
      Keyword.get(opts, :to_user_id),
      Keyword.get(opts, :to),
      "target user",
      "--to EMAIL or --to-user-id UUID"
    )
  end

  defp find_user(id, _email, _label, _hint) when is_binary(id) do
    case Repo.get(User, id) do
      nil -> {:error, "User not found: #{id}"}
      user -> {:ok, user}
    end
  end

  defp find_user(nil, email, _label, _hint) when is_binary(email) do
    case Repo.get_by(User, email: email) do
      nil -> {:error, "User not found: #{email}"}
      user -> {:ok, user}
    end
  end

  defp find_user(nil, nil, label, hint) do
    {:error, "Missing #{label}. Use #{hint}"}
  end

  defp validate_different_users(%{id: id}, %{id: id}),
    do: {:error, "Source and target user are the same"}

  defp validate_different_users(_source, _target), do: :ok

  defp build_transfer(credential, source_user, target_user, final_name, reason) do
    %{
      credential: credential,
      source_user: source_user,
      target_user: target_user,
      final_name: final_name,
      reason: reason
    }
  end

  defp perform_transfer(
         %{
           credential: cred,
           target_user: target,
           final_name: name,
           reason: reason
         } = transfer
       ) do
    source_user = transfer.source_user

    changeset =
      cred
      |> Ecto.Changeset.change(%{user_id: target.id, name: name})
      |> Ecto.Changeset.unique_constraint([:name, :user_id],
        name: "credentials_name_user_id_index",
        message: "credential with this name already exists for target user"
      )

    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated} ->
          audit_metadata = %{
            "from_user_id" => source_user.id,
            "from_user_email" => source_user.email,
            "to_user_id" => target.id,
            "to_user_email" => target.email,
            "reason" => reason,
            "original_name" => cred.name,
            "new_name" => name
          }

          CredentialAudit.event(
            "transferred",
            cred.id,
            source_user,
            %{},
            audit_metadata
          )
          |> CredentialAudit.save()

          %{
            credential_id: updated.id,
            credential_name: updated.name,
            from_email: source_user.email,
            to_email: target.email
          }

        {:error, changeset} ->
          if unique_constraint_error?(changeset) do
            Repo.rollback(
              {:conflict,
               "#{target.email} already has a credential named '#{name}'"}
            )
          else
            Repo.rollback({:error, inspect(changeset.errors)})
          end
      end
    end)
  end

  defp unique_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:name, {_, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end

  defp output_transfer_plan(transfers, format, opts)

  defp output_transfer_plan(transfers, "json", opts) do
    dry_run = Keyword.get(opts, :dry_run, false)

    data = %{
      dry_run: dry_run,
      transfers:
        Enum.map(transfers, fn t ->
          %{
            credential_id: t.credential.id,
            credential_name: t.credential.name,
            from: t.source_user.email,
            to: t.target_user.email,
            rename: if(t.final_name != t.credential.name, do: t.final_name)
          }
        end)
    }

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp output_transfer_plan(_transfers, "quiet", _opts), do: :ok

  defp output_transfer_plan(transfers, "table", opts) do
    dry_run = Keyword.get(opts, :dry_run, false)

    if dry_run do
      info("\n=== Dry Run - No changes will be made ===\n")
    end

    info("Transfer Plan:")
    info(String.duplicate("-", 80))

    Enum.each(transfers, fn t ->
      info("  #{t.credential.name}")
      info("    ID: #{t.credential.id}")
      info("    From: #{t.source_user.email}")
      info("    To: #{t.target_user.email}")

      if t.final_name != t.credential.name do
        info("    Rename to: #{t.final_name}")
      end

      info("")
    end)
  end

  defp output_transfer_result(results, "json") do
    data = %{
      success: true,
      transfers: results
    }

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp output_transfer_result(_results, "quiet"), do: :ok

  defp output_transfer_result(results, "table") do
    info("\n=== Transfer Complete ===\n")

    Enum.each(results, fn r ->
      info("  #{r.credential_name}")
      info("    #{r.from_email} -> #{r.to_email}")
      info("")
    end)

    info("#{length(results)} credential(s) transferred successfully.")
  end

  defp output_credential_list(credentials, user, "json") do
    data = %{
      user: user.email,
      credentials:
        Enum.map(credentials, fn c ->
          %{
            id: c.id,
            name: c.name,
            schema: c.schema,
            projects: Enum.map(c.projects, & &1.name)
          }
        end)
    }

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp output_credential_list(credentials, _user, "quiet") do
    Enum.each(credentials, fn c ->
      IO.puts(c.id)
    end)
  end

  defp output_credential_list(credentials, user, "table") do
    info("\nCredentials for #{user.email}:")
    info(String.duplicate("-", 80))

    if Enum.empty?(credentials) do
      info("  No credentials found.")
    else
      Enum.each(credentials, fn c ->
        projects = Enum.map_join(c.projects, ", ", & &1.name)
        info("  #{c.name}")
        info("    ID: #{c.id}")
        info("    Schema: #{c.schema || "raw"}")
        info("    Projects: #{if projects == "", do: "(none)", else: projects}")
        info("")
      end)

      info("Total: #{length(credentials)} credential(s)")
    end
  end

  defp output_conflicts(conflicts, target_user, "json") do
    data = %{
      conflicts:
        Enum.map(conflicts, fn c ->
          %{id: c.id, name: c.name, target_user: target_user.email}
        end)
    }

    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp output_conflicts(_conflicts, _target_user, "quiet"), do: :ok

  defp output_conflicts(conflicts, target_user, "table") do
    info("\nSkipped due to naming conflicts with #{target_user.email}:")

    Enum.each(conflicts, fn c ->
      info("  - #{c.name} (#{c.id})")
    end)

    info("")
  end

  defp output_error(message, "json") do
    data = %{success: false, error: message}
    IO.puts(Jason.encode!(data, pretty: true))
  end

  defp output_error(message, "quiet") do
    IO.puts(:stderr, message)
  end

  defp output_error(message, "table") do
    Mix.shell().error("Error: #{message}")
  end

  defp output_message(_message, "quiet"), do: :ok

  defp output_message(message, "json"),
    do: IO.puts(Jason.encode!(%{message: message}))

  defp output_message(message, "table"), do: info(message)

  defp info(message), do: Mix.shell().info(message)

  @spec exit_with(non_neg_integer()) :: :ok | no_return()
  defp exit_with(0), do: :ok
  defp exit_with(code), do: exit({:shutdown, code})
end
