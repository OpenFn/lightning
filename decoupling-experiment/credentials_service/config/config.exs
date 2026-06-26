import Config

config :credentials_service,
  ecto_repos: [CredentialsService.Repo]

config :credentials_service, CredentialsService.Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

config :credentials_service, CredentialsServiceWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: CredentialsServiceWeb.ErrorJSON], layout: false],
  # Experiment-only static secret. Real deployments inject this from the env.
  secret_key_base:
    "experiment_only_secret_key_base_padding_padding_padding_padding_0123456789"

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
