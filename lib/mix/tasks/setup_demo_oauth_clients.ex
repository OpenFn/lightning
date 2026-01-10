defmodule Mix.Tasks.Lightning.SetupDemoOauthClients do
  @shortdoc "Set up demo OAuth clients for Google, Salesforce, and Microsoft"

  @moduledoc """
  Sets up demo OAuth clients for Google, Salesforce, and Microsoft services.

  This task creates global OAuth clients that can be used across all projects.
  It will skip any OAuth clients that already exist (by name).

  ## Usage

      mix lightning.setup_demo_oauth_clients [OPTIONS]

  ## Options

    * `--email` - Email of the user who will own the OAuth clients.
      If not provided, uses the first superuser found, or falls back to
      the first user in the system.

  ## Environment Variables

  Each service reads credentials from environment variables (set in `.env`):

  - `GOOGLE_DRIVE_CLIENT_ID`, `GOOGLE_DRIVE_CLIENT_SECRET`
  - `GOOGLE_SHEETS_CLIENT_ID`, `GOOGLE_SHEETS_CLIENT_SECRET`
  - `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`
  - `SALESFORCE_CLIENT_ID`, `SALESFORCE_CLIENT_SECRET`
  - `SALESFORCE_SANDBOX_CLIENT_ID`, `SALESFORCE_SANDBOX_CLIENT_SECRET`
  - `MICROSOFT_SHAREPOINT_CLIENT_ID`, `MICROSOFT_SHAREPOINT_CLIENT_SECRET`
  - `MICROSOFT_OUTLOOK_CLIENT_ID`, `MICROSOFT_OUTLOOK_CLIENT_SECRET`
  - `MICROSOFT_CALENDAR_CLIENT_ID`, `MICROSOFT_CALENDAR_CLIENT_SECRET`
  - `MICROSOFT_ONEDRIVE_CLIENT_ID`, `MICROSOFT_ONEDRIVE_CLIENT_SECRET`
  - `MICROSOFT_TEAMS_CLIENT_ID`, `MICROSOFT_TEAMS_CLIENT_SECRET`

  If environment variables are not set, placeholder values will be used.

  ## Examples

      # Use default user (first superuser or first user)
      mix lightning.setup_demo_oauth_clients

      # Specify a user by email
      mix lightning.setup_demo_oauth_clients --email admin@example.com

  ## Created OAuth Clients

  - **Google**: Google Drive, Google Sheets, Gmail
  - **Salesforce**: Salesforce (production), Salesforce Sandbox
  - **Microsoft**: SharePoint, Outlook, Calendar, OneDrive, Teams
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [email: :string],
        aliases: [e: :email]
      )

    if length(invalid) > 0 do
      invalid_opts = Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)

      Mix.raise("""
      Unknown option(s): #{invalid_opts}

      Valid options:
        --email EMAIL    Email of the user who will own the OAuth clients

      Run `mix help lightning.setup_demo_oauth_clients` for more information.
      """)
    end

    Mix.Task.run("app.start")

    setup_opts = if opts[:email], do: [user_email: opts[:email]], else: []

    case Lightning.SetupUtils.setup_demo_oauth_clients(setup_opts) do
      {:ok, oauth_clients} ->
        print_results(oauth_clients)

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

  defp print_results(oauth_clients) do
    {created, skipped} =
      Enum.split_with(oauth_clients, fn {_key, value} -> value != :skipped end)

    if length(created) > 0 do
      Mix.shell().info("\nCreated OAuth clients:")

      Enum.each(created, fn {key, client} ->
        Mix.shell().info("  ✓ #{client.name} (#{key})")
      end)
    end

    if length(skipped) > 0 do
      Mix.shell().info("\nSkipped (already exist):")

      Enum.each(skipped, fn {key, _} ->
        name =
          key
          |> Atom.to_string()
          |> String.replace("_", " ")
          |> String.split()
          |> Enum.map(&String.capitalize/1)
          |> Enum.join(" ")

        Mix.shell().info("  - #{name}")
      end)
    end

    total_created = length(created)
    total_skipped = length(skipped)

    Mix.shell().info(
      "\nDone! Created #{total_created} OAuth client(s), skipped #{total_skipped}."
    )
  end
end
