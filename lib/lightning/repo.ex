defmodule Lightning.Repo do
  use Ecto.Repo,
    otp_app: :lightning,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 10, max_page_size: 100
end
