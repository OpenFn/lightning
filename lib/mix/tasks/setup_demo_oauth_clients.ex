defmodule Mix.Tasks.Lightning.SetupDemoOauthClients do
  @shortdoc "Set up demo OAuth clients and optional dummy credentials"

  @moduledoc """
  Sets up demo OAuth clients for Google, Salesforce, and Microsoft services,
  with optional dummy credentials that users can reauthorize later.

  This task creates global OAuth clients that can be used across all projects.
  It will skip any OAuth clients that already exist (by name).

  ## Usage

      mix lightning.setup_demo_oauth_clients [OPTIONS]

  ## Options

    * `--email` - Email of the user who will own the OAuth clients.
      If not provided, uses the first superuser found, or falls back to
      the first user in the system.

    * `--only` - Comma-separated list of client keys to create.
      If omitted, creates all configured clients.

    * `--list` - Show available clients and their configuration status,
      then exit without creating anything.

    * `--credentials` - Also create dummy OAuth credentials for each
      OAuth client. Users can reauthorize these later through the UI.

    * `--project` - Attach created credentials to this project (by ID).
      Only used with `--credentials`.

  ## Available client keys

      google_drive, google_sheets, gmail,
      salesforce, salesforce_sandbox,
      microsoft_sharepoint, microsoft_outlook, microsoft_calendar,
      microsoft_onedrive, microsoft_teams

  ## Environment Variables

  Each service requires two environment variables (set in `.env`):

  - `{SERVICE}_CLIENT_ID` - The OAuth client ID
  - `{SERVICE}_CLIENT_SECRET` - The OAuth client secret

  Where `{SERVICE}` matches the uppercased client key
  (e.g., `GOOGLE_SHEETS_CLIENT_ID` for `google_sheets`).

  ## Examples

      # Show what's available and what's configured
      mix lightning.setup_demo_oauth_clients --list

      # Create all configured OAuth clients
      mix lightning.setup_demo_oauth_clients

      # Create only Google Sheets and Salesforce
      mix lightning.setup_demo_oauth_clients --only google_sheets,salesforce

      # Create OAuth clients + dummy credentials
      mix lightning.setup_demo_oauth_clients --credentials

      # Create OAuth clients + dummy credentials attached to a project
      mix lightning.setup_demo_oauth_clients --credentials --project <project-id>

      # Specify a user by email
      mix lightning.setup_demo_oauth_clients --email admin@example.com --only gmail
  """

  use Mix.Task

  alias Lightning.SetupUtils

  @valid_keys SetupUtils.all_keys()

  @impl Mix.Task
  def run(args) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [
          email: :string,
          only: :string,
          list: :boolean,
          credentials: :boolean,
          project: :string
        ],
        aliases: [e: :email, o: :only, l: :list, c: :credentials, p: :project]
      )

    if invalid != [] do
      invalid_opts = Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)

      Mix.raise("""
      Unknown option(s): #{invalid_opts}

      Run `mix help lightning.setup_demo_oauth_clients` for more information.
      """)
    end

    if opts[:project] && !opts[:credentials] do
      Mix.raise("""
      --project requires --credentials.

      Use: mix lightning.setup_demo_oauth_clients --credentials --project <id>
      """)
    end

    Mix.Task.run("app.start")

    if opts[:list] do
      print_available_clients()
    else
      create_clients(opts)
    end
  end

  defp print_available_clients do
    clients = SetupUtils.list_demo_oauth_clients()

    configured =
      Enum.filter(clients, fn {_, status} -> status == :configured end)

    not_configured =
      Enum.filter(clients, fn {_, status} -> status == :not_configured end)

    Mix.shell().info("\nAvailable demo OAuth clients:\n")

    if configured != [] do
      Mix.shell().info("  Ready to create:")

      Enum.each(configured, fn {key, _} ->
        Mix.shell().info("    ✓ #{key}")
      end)

      Mix.shell().info("")
    end

    if not_configured != [] do
      Mix.shell().info("  Missing OAuth client configuration:")

      Enum.each(not_configured, fn {key, _} ->
        {id_var, secret_var} = SetupUtils.env_vars_for(key)
        Mix.shell().info("    ✗ #{key}")
        Mix.shell().info("      #{id_var}")
        Mix.shell().info("      #{secret_var}")
      end)

      Mix.shell().info("")
    end

    Mix.shell().info(
      "  #{length(configured)} configured, #{length(not_configured)} missing configuration\n"
    )
  end

  defp create_clients(opts) do
    only = parse_only(opts[:only])

    setup_opts =
      Enum.reject(
        [user_email: opts[:email], only: only],
        fn {_k, v} -> is_nil(v) end
      )

    case SetupUtils.setup_demo_oauth_clients(setup_opts) do
      {:ok, client_results} ->
        print_client_results(client_results)

        if opts[:credentials] do
          create_credentials(opts, only)
        end

      {:error, :no_users_found} ->
        Mix.raise("""
        No users found in the database.

        Please create at least one user before running this task:
          mix run -e 'Lightning.SetupUtils.setup_demo()'
        """)

      {:error, :user_not_found} ->
        Mix.raise("""
        User not found with email: #{opts[:email]}

        Please check the email address and try again.
        """)
    end
  end

  defp create_credentials(opts, only) do
    cred_opts =
      Enum.reject(
        [user_email: opts[:email], only: only, project_id: opts[:project]],
        fn {_k, v} -> is_nil(v) end
      )

    case SetupUtils.setup_demo_oauth_credentials(cred_opts) do
      {:ok, cred_results} ->
        print_credential_results(cred_results)

      {:error, :no_users_found} ->
        Mix.raise("No users found.")

      {:error, :user_not_found} ->
        Mix.raise("User not found with email: #{opts[:email]}")
    end
  end

  defp parse_only(nil), do: nil

  defp parse_only(value) do
    valid_strings = Enum.map(@valid_keys, &Atom.to_string/1)

    strings =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    invalid = strings -- valid_strings

    if invalid != [] do
      Mix.raise("""
      Unknown client key(s): #{Enum.join(invalid, ", ")}

      Available keys: #{Enum.join(@valid_keys, ", ")}
      """)
    end

    Enum.map(strings, &String.to_existing_atom/1)
  end

  defp print_client_results(results) do
    created =
      Enum.filter(results, fn {_, v} -> not is_atom(v) end)

    skipped =
      Enum.filter(results, fn {_, v} -> v == :skipped end)

    not_configured =
      Enum.filter(results, fn {_, v} -> v == :not_configured end)

    if created != [] do
      Mix.shell().info("\nOAuth clients created:")

      Enum.each(created, fn {key, client} ->
        Mix.shell().info("  ✓ #{client.name} (#{key})")
      end)
    end

    if skipped != [] do
      Mix.shell().info("\nOAuth clients already exist:")

      Enum.each(skipped, fn {key, _} ->
        Mix.shell().info("  - #{SetupUtils.demo_client_name(key)}")
      end)
    end

    if not_configured != [] do
      Mix.shell().info("\nMissing OAuth client configuration:")

      Enum.each(not_configured, fn {key, _} ->
        {id_var, secret_var} = SetupUtils.env_vars_for(key)

        Mix.shell().info(
          "  ✗ #{SetupUtils.demo_client_name(key)} (set #{id_var}, #{secret_var})"
        )
      end)
    end

    if created == [] and not_configured != [] and skipped == [] do
      Mix.shell().info("""

      No clients were created. Set the CLIENT_ID and CLIENT_SECRET environment variables for the
      services you need, then run this task again. Use --list to see all options.
      """)
    else
      Mix.shell().info(
        "\nClients: #{length(created)} created, #{length(skipped)} skipped, #{length(not_configured)} not configured."
      )
    end
  end

  defp print_credential_results(results) do
    created =
      Enum.filter(results, fn {_, v} -> not is_atom(v) end)

    skipped =
      Enum.filter(results, fn {_, v} -> v == :skipped end)

    no_client =
      Enum.filter(results, fn {_, v} -> v == :no_oauth_client end)

    if created != [] do
      Mix.shell().info("\nCredentials created:")

      Enum.each(created, fn {key, cred} ->
        Mix.shell().info("  ✓ #{cred.name} (#{key})")
      end)

      Mix.shell().info(
        "\n  These credentials have placeholder tokens. Users should reauthorize\n  through the UI to get real access tokens."
      )
    end

    if skipped != [] do
      Mix.shell().info("\nCredentials already exist:")

      Enum.each(skipped, fn {key, _} ->
        Mix.shell().info("  - #{SetupUtils.demo_client_name(key)} - demo")
      end)
    end

    if no_client != [] do
      Mix.shell().info("\nNo OAuth client found for:")

      Enum.each(no_client, fn {key, _} ->
        Mix.shell().info("  ✗ #{SetupUtils.demo_client_name(key)}")
      end)
    end

    Mix.shell().info(
      "\nCredentials: #{length(created)} created, #{length(skipped)} skipped, #{length(no_client)} missing client."
    )
  end
end
