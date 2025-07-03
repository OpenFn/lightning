defmodule Lightning.Adaptors do
  @moduledoc """
  Adaptor registry

  This module provides a strategy-based adaptor registry that can fetch adaptors
  from different sources (NPM, local repositories, etc.) and cache them efficiently.

  ## Usage

  Start the Adaptors process in your supervision tree:

      children = [
        {Lightning.Adaptors, [
          strategy: {Lightning.Adaptors.NPMStrategy, []},
          persist_path: "/tmp/adaptors_cache"
        ]}
      ]

  Then call functions without passing config:

      Lightning.Adaptors.all()
      Lightning.Adaptors.versions_for("@openfn/language-http")

  You can also create facade modules for different configurations:

      defmodule MyApp.Adaptors do
        use Lightning.Adaptors.Service, otp_app: :my_app
      end

  And configure them in your config files:

      config :my_app, MyApp.Adaptors,
        strategy: {Lightning.Adaptors.NPMStrategy, []},
        persist_path: "/tmp/my_app_adaptors"

  ## Caching Strategy

  The registry uses a two-level caching approach:
  1. Individual adaptors are cached by their name for efficient lookup
  2. A list of all adaptor names is cached under the `"adaptors"` key

  This allows both fast listing (for AdaptorPicker) and fast individual lookups
  (for versions_for/latest_for functions).

  ## Persistence

  The cache can be persisted to disk and restored across application restarts
  using the `:persist_path` configuration option. When provided, the cache will
  be automatically restored on first access and saved after updates.
  """

  use Lightning.Adaptors.Service, otp_app: :lightning

  def packages_filter(name) do
    name not in [
      "@openfn/language-devtools",
      "@openfn/language-template",
      "@openfn/language-fhir-jembi",
      "@openfn/language-collections"
    ] &&
      Regex.match?(~r/@openfn\/language-\w+/, name)
  end
end
