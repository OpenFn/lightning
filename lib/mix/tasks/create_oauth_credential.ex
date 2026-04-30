defmodule Mix.Tasks.Lightning.CreateOauthCredential do
  @shortdoc "Create a dummy OAuth credential for an existing OAuth client"

  @moduledoc """
  Creates a dummy OAuth credential with placeholder tokens that users
  can reauthorize later through the UI.

  ## Usage

      mix lightning.create_oauth_credential --client <name-or-id> [OPTIONS]

  ## Options

    * `--list` - Show available OAuth clients and exit.

    * `--client` (required) - OAuth client to create the credential for.
      Accepts a client name (e.g., "Google Sheets") or UUID.

    * `--name` - Custom credential name.
      Defaults to "<client name> - demo".

    * `--user` - Email of the user who will own the credential.
      If not provided, uses the first superuser found, or falls back to
      the first user in the system.

    * `--project` - Project ID to attach the credential to.

  ## Examples

      # List available OAuth clients
      mix lightning.create_oauth_credential --list

      # Create a credential for Google Sheets
      mix lightning.create_oauth_credential --client "Google Sheets"

      # Custom name
      mix lightning.create_oauth_credential --client "Google Sheets" --name "My GSheets Cred"

      # Attach to a project
      mix lightning.create_oauth_credential --client salesforce --project <project-id>

      # Specify owner
      mix lightning.create_oauth_credential --client gmail --user dev@example.com

  ## Notes

  The credential is created with placeholder tokens. Users must reauthorize
  through the Lightning UI to get real access tokens.
  """

  use Mix.Task

  alias Lightning.Credentials.OauthClient
  alias Lightning.Repo
  alias Lightning.SetupUtils

  import Ecto.Query

  @impl Mix.Task
  def run(args) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [
          client: :string,
          name: :string,
          user: :string,
          project: :string,
          list: :boolean
        ],
        aliases: [c: :client, n: :name, u: :user, p: :project, l: :list]
      )

    if invalid != [] do
      invalid_opts = Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)

      Mix.raise("""
      Unknown option(s): #{invalid_opts}

      Run `mix help lightning.create_oauth_credential` for more information.
      """)
    end

    Mix.Task.run("app.start")

    if opts[:list] do
      list_oauth_clients()
    else
      unless opts[:client] do
        Mix.raise("""
        --client is required.

        Usage: mix lightning.create_oauth_credential --client <name-or-id>

        Use --list to see available OAuth clients.
        """)
      end

      create_credential(opts)
    end
  end

  defp list_oauth_clients do
    clients =
      from(c in OauthClient, order_by: [asc: fragment("lower(?)", c.name)])
      |> Repo.all()

    if clients == [] do
      Mix.shell().info("""

      No OAuth clients found.

      Create some first:
        mix lightning.setup_demo_oauth_clients
      """)
    else
      Mix.shell().info("\nAvailable OAuth clients:\n")

      Enum.each(clients, fn client ->
        global = if client.global, do: " (global)", else: ""
        Mix.shell().info("  - #{client.name}#{global}")
        Mix.shell().info("    ID: #{client.id}")
      end)

      Mix.shell().info(
        "\nUse --client \"<name>\" to create a credential for one of these.\n"
      )
    end
  end

  defp create_credential(opts) do
    with {:ok, oauth_client} <- find_oauth_client(opts[:client]),
         {:ok, user} <- find_user(opts[:user]) do
      cred_opts =
        Enum.reject(
          [name: opts[:name], project_id: opts[:project]],
          fn {_k, v} -> is_nil(v) end
        )

      case SetupUtils.create_dummy_oauth_credential(
             oauth_client,
             user,
             cred_opts
           ) do
        {:ok, credential} ->
          credential =
            Repo.preload(credential, [:oauth_client, :project_credentials])

          Mix.shell().info("\n✓ Created credential: #{credential.name}")
          Mix.shell().info("  OAuth client: #{oauth_client.name}")
          Mix.shell().info("  Owner: #{user.email}")

          case credential.project_credentials do
            [pc | _] ->
              Mix.shell().info("  Project: #{pc.project_id}")

            [] ->
              Mix.shell().info("  Project: (none)")
          end

          Mix.shell().info(
            "\n  This credential has placeholder tokens. Reauthorize through\n  the Lightning UI to get real access tokens.\n"
          )

        {:error, %Ecto.Changeset{} = changeset} ->
          errors =
            Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
                opts
                |> Keyword.get(String.to_existing_atom(key), key)
                |> to_string()
              end)
            end)

          Mix.raise("Failed to create credential: #{inspect(errors)}")

        {:error, %Lightning.Credentials.OauthValidation.Error{} = error} ->
          Mix.raise("Token validation failed: #{inspect(error)}")

        {:error, reason} ->
          Mix.raise("Failed to create credential: #{inspect(reason)}")
      end
    end
  end

  defp find_oauth_client(client_ref) do
    # Try UUID first, then name
    query =
      if match?({:ok, _}, Ecto.UUID.cast(client_ref)) do
        from(c in OauthClient, where: c.id == ^client_ref)
      else
        from(c in OauthClient, where: c.name == ^client_ref)
      end

    case Repo.one(query) do
      nil ->
        available =
          from(c in OauthClient, select: c.name, order_by: [asc: c.name])
          |> Repo.all()

        if available == [] do
          Mix.raise("""
          No OAuth client found matching "#{client_ref}".

          No OAuth clients exist yet. Create some first:
            mix lightning.setup_demo_oauth_clients
          """)
        else
          Mix.raise("""
          No OAuth client found matching "#{client_ref}".

          Available OAuth clients:
          #{Enum.map_join(available, "\n", &"  - #{&1}")}
          """)
        end

      client ->
        {:ok, client}
    end
  end

  defp find_user(nil) do
    alias Lightning.Accounts.User

    case Repo.one(from(u in User, where: u.role == :superuser, limit: 1)) do
      nil ->
        case Repo.one(from(u in User, limit: 1)) do
          nil ->
            Mix.raise("""
            No users found in the database.

            Please create at least one user before running this task:
              mix run -e 'Lightning.SetupUtils.setup_demo()'
            """)

          user ->
            {:ok, user}
        end

      user ->
        {:ok, user}
    end
  end

  defp find_user(email) do
    case Lightning.Accounts.get_user_by_email(email) do
      nil ->
        Mix.raise("""
        User not found with email: #{email}

        Please check the email address and try again.
        """)

      user ->
        {:ok, user}
    end
  end
end
