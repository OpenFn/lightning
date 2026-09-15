[
  import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{heex,ex,exs}",
    "priv/*/seeds.exs",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "tooling/adaptor_cache/lib/**/*.ex",
    "bin/adaptor_cache"
  ],
  subdirectories: ["priv/*/migrations"],
  line_length: 81
]
