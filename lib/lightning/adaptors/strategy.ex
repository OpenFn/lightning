defmodule Lightning.Adaptors.Strategy do
  @moduledoc """
  Behaviour shared by every adaptor strategy (NPM, Local, and the test
  mock).

  A strategy is the sole boundary between the `Lightning.Adaptors.*`
  subsystem and the outside world. It defines four callbacks:

    * `c:fetch_adaptor/1` — given a package name, return a structured
      `t:adaptor_record/0` covering version history, integrity hashes,
      and dependency metadata. Icon fields are **not** part of this
      record any more; the Scheduler stamps them on after joining the
      bulk icon pipeline.
    * `c:fetch_icon/2` — given a package name and an icon variant,
      return the raw bytes plus extension. Used by the Store's rare
      lazy-miss fallback.
    * `c:fetch_icons/1` — bulk icon fetch for every adaptor known to
      the strategy. The Scheduler invokes this once per tick in parallel
      with its per-adaptor fan-out. Accepts a keyword list of options;
      see the callback docs for `:prior_etags`.
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
  fields are persisted separately by the Scheduler after joining
  `c:fetch_icons/1` — they are not stamped onto this record.
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
          versions: [version_record()]
        }

  @typedoc """
  Fresh-fetch icon entry inside the `c:fetch_icons/1` result map. The
  optional `:etag` field carries the upstream-provided cache validator
  (verbatim from the HTTP response) and is `nil` when the upstream
  didn't supply one — strategies without a transport-level validator
  (e.g. `Lightning.Adaptors.Local`) omit the key entirely.
  """
  @type icon_entry :: %{
          required(:data) => binary(),
          required(:ext) => String.t(),
          required(:sha256) => binary(),
          optional(:etag) => String.t() | nil
        }

  @typedoc """
  Per-shape value inside the `c:fetch_icons/1` result map. Either a
  fresh `t:icon_entry/0` (200 response) or the `:not_modified` sentinel
  (304 response — upstream confirmed unchanged; only ever returned when
  the caller supplied a prior etag via the `:prior_etags` option).
  """
  @type icon_shape_value :: icon_entry() | :not_modified

  @typedoc """
  Bulk icon map returned by `c:fetch_icons/1`. Three branches matter:

    * shape **entirely absent** — upstream had no such icon for this
      package;
    * shape present as `:not_modified` — upstream confirmed the icon
      is unchanged since the prior etag was issued;
    * shape present as a map — apply the bytes (a fresh fetch).
  """
  @type icons_map :: %{
          required(String.t()) => %{
            optional(:square) => icon_shape_value(),
            optional(:rectangle) => icon_shape_value()
          }
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
  Bulk fetch every available icon for every adaptor known to the
  strategy.

  Returns `{:ok, partial_map}` where each per-shape slot is either
  absent (no icon upstream), a fresh `t:icon_entry/0` (200), or the
  `:not_modified` sentinel (304 — only when a prior etag was sent).
  A top-level `{:error, term()}` is only returned when the whole
  pipeline can't proceed (e.g. an upstream `list_adaptors/0` call
  inside the bulk implementation fails).

  ## Options

    * `:prior_etags` — a map of the form
      `%{name => %{optional(:square | :rectangle) => etag_string}}`
      whose values are sent as `If-None-Match` per `(name, shape)`.
      Defaults to `%{}`. Unknown keys in the keyword list are
      ignored. Strategies without a transport-level cache validator
      (e.g. `Lightning.Adaptors.Local`) ignore this option entirely
      and never return `:not_modified`.
  """
  @callback fetch_icons(opts :: keyword()) ::
              {:ok, icons_map()} | {:error, term()}

  @doc """
  Cheap change-signal listing: `name + latest_version` for every
  `@openfn/*` package known to the strategy. The scheduler diffs this
  against the `adaptors` table to compute its work list.
  """
  @callback list_adaptors() ::
              {:ok, [%{name: String.t(), latest_version: String.t()}]}
              | {:error, term()}
end
