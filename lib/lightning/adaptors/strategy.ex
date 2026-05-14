defmodule Lightning.Adaptors.Strategy do
  @moduledoc """
  Behaviour shared by every adaptor strategy (NPM, Local, and the test
  mock).

  A strategy is the sole boundary between the `Lightning.Adaptors.*`
  subsystem and the outside world. It defines three callbacks:

    * `c:fetch_adaptor/1` — given a package name, return a structured
      `t:adaptor_record/0` covering version history, integrity hashes,
      and dependency metadata.
    * `c:fetch_icon/2` — given a package name and an icon variant,
      return the raw bytes plus extension.
    * `c:list_adaptors/0` — the cheap change-signal: one call returning
      `name + latest_version` for every `@openfn/*` package, used by
      the scheduler to diff against the `adaptors` table.

  The active strategy module is resolved at runtime via
  `Lightning.Adaptors.Config.strategy/0`. Implementations must surface
  transient failures (5xx, timeout, nxdomain) as `{:error, term()}`;
  retry policy lives at the scheduler/store layer, not here.
  """

  @typedoc """
  Per-version metadata extracted from an upstream packument or local
  `package.json`.
  """
  @type version_record :: %{
          version: String.t(),
          integrity: String.t() | nil,
          tarball_url: String.t() | nil,
          size_bytes: integer() | nil,
          dependencies: map(),
          peer_dependencies: map(),
          published_at: DateTime.t() | nil,
          deprecated: boolean()
        }

  @typedoc """
  The structured adaptor record returned by `c:fetch_adaptor/1`. Icon
  hash fields are 32 raw bytes; the `_sha256` field is `nil` iff the
  matching `_ext` field is `nil`.
  """
  @type adaptor_record :: %{
          name: String.t(),
          description: String.t() | nil,
          homepage: String.t() | nil,
          repository: String.t() | nil,
          license: String.t() | nil,
          latest_version: String.t(),
          deprecated: boolean(),
          schema_data: map() | nil,
          schema_sha256: String.t() | nil,
          icon_square_ext: String.t() | nil,
          icon_rectangle_ext: String.t() | nil,
          icon_square_sha256: binary() | nil,
          icon_rectangle_sha256: binary() | nil,
          versions: [version_record()]
        }

  @doc """
  Fetch the full structured record for a single adaptor package.
  """
  @callback fetch_adaptor(name :: String.t()) ::
              {:ok, adaptor_record()} | {:error, term()}

  @doc """
  Fetch the raw bytes for one icon variant (`:square` or `:rectangle`)
  of an adaptor package, together with the file extension.
  """
  @callback fetch_icon(name :: String.t(), :square | :rectangle) ::
              {:ok, %{data: binary(), ext: String.t()}}
              | {:error, term()}

  @doc """
  Cheap change-signal listing: `name + latest_version` for every
  `@openfn/*` package known to the strategy. The scheduler diffs this
  against the `adaptors` table to compute its work list.
  """
  @callback list_adaptors() ::
              {:ok, [%{name: String.t(), latest_version: String.t()}]}
              | {:error, term()}
end
