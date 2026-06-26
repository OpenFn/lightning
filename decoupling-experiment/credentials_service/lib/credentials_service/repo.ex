defmodule CredentialsService.Repo do
  use Ecto.Repo,
    otp_app: :credentials_service,
    adapter: Ecto.Adapters.Postgres
end
