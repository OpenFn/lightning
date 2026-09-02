defmodule Lightning.Adaptors do
  @moduledoc """
  The adaptor catalogue: which npm adaptors exist, their versions, schemas
  and icons.

  A scheduler fetches the catalogue from the configured source and
  persists it. Reads check an in-memory cache first and the database
  second. The first read against an empty catalogue triggers the initial
  load and waits for it, bounded by the first-load timeout, and returns an
  error if the load does not complete in time.

  ## Adaptor specs

  A spec is the `name@version` string a job stores, where the version is
  a semver or one of two sentinels: `latest` resolves to the catalogue's
  current version when the job runs, and `local` points the worker at an
  adaptor on its own filesystem. The version may also be omitted.

  ## Configuration

  Under `config :lightning, Lightning.Adaptors`:

    * `:strategy` - the module that fetches from the source
    * `:refresh_interval` - how often the scheduler re-checks the source,
      in milliseconds; `0` disables the periodic tick
    * `:first_load_timeout` - how long a read waits for the initial load
    * `:cache_timeout_ms` - how long a read waits for a cache fill
    * `:icon_path` - where fetched icons are written

  Defaults are in `Lightning.Adaptors.Config`.

  ## Testing

  Every function that talks to a running process takes the supervisor
  name as an optional first argument, defaulting to `Lightning.Adaptors`.
  Start a `Lightning.Adaptors.Supervisor` under another name and pass
  that name to run a test against its own catalogue and cache.
  """

  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.PackageName
  alias Lightning.Adaptors.Scheduler
  alias Lightning.Adaptors.Store
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  defmodule Package do
    @moduledoc """
    One catalogue adaptor.
    """

    defmodule Version do
      @moduledoc """
      One published version of a catalogue adaptor.
      """

      @type t :: %__MODULE__{
              version: String.t(),
              integrity: String.t() | nil,
              size_bytes: integer() | nil,
              published_at: DateTime.t() | nil,
              deprecated: boolean()
            }

      defstruct [
        :version,
        :integrity,
        :size_bytes,
        :published_at,
        deprecated: false
      ]
    end

    @type t :: %__MODULE__{
            name: String.t(),
            source: :npm | :local,
            latest_version: String.t() | nil,
            description: String.t() | nil,
            deprecated: boolean(),
            icon_square_ext: String.t() | nil,
            icon_rectangle_ext: String.t() | nil,
            icon_square_sha256: binary() | nil,
            icon_rectangle_sha256: binary() | nil
          }

    defstruct [
      :name,
      :source,
      :latest_version,
      :description,
      :icon_square_ext,
      :icon_rectangle_ext,
      :icon_square_sha256,
      :icon_rectangle_sha256,
      deprecated: false
    ]
  end

  @sup Lightning.Adaptors

  @doc """
  Returns every adaptor in the catalogue as `Package` structs.
  """
  @spec packages(atom()) :: {:ok, [Package.t()]} | {:error, :timeout | term()}
  def packages(sup \\ @sup) do
    with {:ok, metas} <- Store.packages(sup) do
      source = AdaptorsSupervisor.source(sup)
      {:ok, Enum.map(metas, &to_package(&1, source))}
    end
  end

  @doc """
  Returns the credential schema of the adaptor named `pkg`, as a JSON
  binary.
  """
  @spec schema(atom(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def schema(sup \\ @sup, pkg), do: Store.schema(sup, pkg)

  @doc """
  Returns the on-disk path of the adaptor's `:square` or `:rectangle`
  icon, fetching it on the first request.
  """
  @spec icon(atom(), String.t(), :square | :rectangle) ::
          {:ok, Path.t()} | {:error, term()}
  def icon(sup \\ @sup, pkg, shape), do: Store.icon(sup, pkg, shape)

  @doc """
  Returns the picker catalogue as `{{latest_updated_at, count}, entries}`:
  every adaptor with its full version list and icon URLs, rendered once
  per change rather than per request, alongside the ETag basis for it.

  One read, so the stamp always describes the entries it comes with.
  """
  @spec catalogue_with_stamp(atom()) ::
          {{DateTime.t() | nil, non_neg_integer()}, [Store.catalogue_entry()]}
  def catalogue_with_stamp(sup \\ @sup) do
    {:ok, catalogue} = Store.catalogue(sup)
    catalogue
  end

  @doc """
  Returns the adaptor named `name`, or `nil`.

  Takes a bare package name, not a spec; see `parse_spec/1`. Never waits
  for the catalogue to load; see `fetch_adaptor/2` for that.
  """
  @spec get_adaptor(atom(), String.t()) :: Package.t() | nil
  def get_adaptor(sup \\ @sup, name) when is_binary(name),
    do: lookup(sup, name)

  @doc """
  Returns `{:ok, adaptor}` for the adaptor named `name`, waiting for the
  catalogue's first load if it has never loaded.

  Errors:

    * `{:error, :not_found}` - the loaded catalogue has no such adaptor
    * `{:error, :timeout}` - the first load did not finish within
      `Lightning.Adaptors.Config.first_load_timeout/0`
    * `{:error, :unavailable}` - no Scheduler process is reachable
    * `{:error, :not_ready}` - the load ran but left the catalogue empty
  """
  @spec fetch_adaptor(atom(), String.t()) ::
          {:ok, Package.t()}
          | {:error, :not_found | :timeout | :unavailable | :not_ready}
  def fetch_adaptor(sup \\ @sup, name) when is_binary(name) do
    case lookup(sup, name) do
      %Package{} = package ->
        {:ok, package}

      nil ->
        if ready?(sup),
          do: {:error, :not_found},
          else: load_then_fetch(sup, name)
    end
  end

  defp load_then_fetch(sup, name) do
    with :ok <- load(sup) do
      case lookup(sup, name) do
        %Package{} = package -> {:ok, package}
        nil -> {:error, :not_found}
      end
    end
  end

  # Cache first, then the row itself: the cached list can lag a Scheduler
  # write until the Invalidator drops it.
  defp lookup(sup, name) do
    source = AdaptorsSupervisor.source(sup)

    cached =
      case Store.packages(sup) do
        {:ok, metas} -> Enum.find(metas, &(&1.name == name))
        {:error, _} -> nil
      end

    case cached || Catalogue.get_adaptor(name, source) do
      nil -> nil
      meta -> to_package(meta, source)
    end
  end

  defp to_package(meta, source) do
    struct(Package, meta |> Map.delete(:__struct__) |> Map.put(:source, source))
  end

  @doc """
  Waits until the catalogue has loaded at least once, triggering the
  first load if needed.

  Returns `:ok`, or one of the `fetch_adaptor/2` errors other than
  `:not_found`.
  """
  @spec ensure_loaded(atom()) ::
          :ok | {:error, :timeout | :unavailable | :not_ready}
  def ensure_loaded(sup \\ @sup) do
    if ready?(sup), do: :ok, else: load(sup)
  end

  defp load(sup) do
    case refresh(sup, await: true) do
      {:error, :timeout} -> {:error, :timeout}
      {:error, :unavailable} -> {:error, :unavailable}
      # A successful cycle can still leave the source empty, and a failed
      # one can land on rows a seed already wrote.
      _ -> if ready?(sup), do: :ok, else: {:error, :not_ready}
    end
  end

  defp ready?(sup),
    do: Catalogue.max_checked_at(AdaptorsSupervisor.source(sup)) != nil

  @doc """
  Splits an adaptor spec into `{name, version}`, with `version` `nil` when
  the spec carries none, and `{nil, nil}` for a malformed spec.
  """
  @spec parse_spec(String.t()) :: {String.t() | nil, String.t() | nil}
  def parse_spec(spec) when is_binary(spec) do
    case Regex.run(PackageName.strict_format(), spec) do
      [_, name, version] -> {name, version}
      [_, name] -> {name, nil}
      _ -> {nil, nil}
    end
  end

  @doc """
  Returns whether `spec` is a well-formed adaptor spec: a package name
  plus an optional `@version`, with no newlines or shell metacharacters.
  """
  @spec valid_format?(String.t()) :: boolean()
  def valid_format?(spec) when is_binary(spec),
    do: Regex.match?(PackageName.strict_format(), spec)

  @doc """
  Renders an adaptor spec for the worker: `latest` becomes the
  catalogue's current version, `local` is kept, and a `:local` source
  forces `name@local`. A `nil` spec renders as `""`.
  """
  @spec to_wire(atom(), String.t() | nil) ::
          {:ok, String.t()}
          | {:error, :not_found | :timeout | :unavailable | :not_ready}
  def to_wire(sup \\ @sup, spec)

  def to_wire(_sup, nil), do: {:ok, ""}

  def to_wire(sup, spec) when is_binary(spec) do
    source = AdaptorsSupervisor.source(sup)

    case parse_spec(spec) do
      {name, "latest"} when source != :local ->
        with {:ok, %Package{latest_version: latest}} <- fetch_adaptor(sup, name) do
          {:ok, PackageName.to_wire(spec, source: source, latest: latest)}
        end

      _ ->
        {:ok, PackageName.to_wire(spec, source: source)}
    end
  end

  @doc """
  Starts a catalogue refresh, or joins one already running.

  Returns `:ok` as soon as the refresh is underway. With `await: true`,
  blocks until the cycle completes, bounded by `:timeout` (default
  `Lightning.Adaptors.Config.first_load_timeout/0`), and returns
  `{:ok, counts}` or `{:error, reason}`; see
  `Lightning.Adaptors.Scheduler.await_refresh/2` for the counts.
  """
  @spec refresh(atom(), keyword()) ::
          :ok | {:ok, Scheduler.refresh_counts()} | {:error, term()}
  def refresh(opts) when is_list(opts), do: refresh(@sup, opts)

  def refresh(sup \\ @sup, opts \\ []) do
    scheduler = AdaptorsSupervisor.global_scheduler_name(sup)

    if opts[:await] do
      timeout = opts[:timeout] || Config.first_load_timeout()
      Scheduler.await_refresh(scheduler, timeout)
    else
      Scheduler.refresh_now(scheduler)
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _reason -> {:error, :unavailable}
  end

  @doc """
  Refetches the adaptor named `name` from the source and persists it,
  whether or not its version changed.
  """
  @spec refresh_package(atom(), String.t()) ::
          :ok | {:error, :not_found | term()}
  def refresh_package(sup \\ @sup, name) when is_binary(name) do
    Scheduler.refresh_package(
      AdaptorsSupervisor.global_scheduler_name(sup),
      name
    )
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _reason -> {:error, :unavailable}
  end

  @doc """
  Refetches every adaptor's icons and updates those whose bytes changed.
  Returns `{:ok, %{updated: n, unchanged: m}}`.
  """
  @spec refresh_icons(atom()) ::
          {:ok, %{updated: non_neg_integer(), unchanged: non_neg_integer()}}
          | {:error, term()}
  def refresh_icons(sup \\ @sup) do
    Scheduler.refresh_icons(AdaptorsSupervisor.global_scheduler_name(sup))
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _reason -> {:error, :unavailable}
  end

  @doc """
  Returns the stored extension and sha256 of each icon shape for the
  adaptor named `name`, without touching disk. See
  `t:Lightning.Adaptors.Store.icon_meta/0`.
  """
  @spec icon_meta(atom(), String.t()) ::
          {:ok, Store.icon_meta()} | {:error, :not_found}
  def icon_meta(sup \\ @sup, name), do: Store.icon_meta(sup, name)

  @doc """
  Subscribes the calling process to catalogue update broadcasts.

  Updates arrive as `%{event: "adaptors_updated", payload: %{names: [...]}}`
  messages.
  """
  @spec subscribe_to_updates(atom()) :: :ok | {:error, term()}
  def subscribe_to_updates(sup \\ @sup) do
    Phoenix.PubSub.subscribe(
      Lightning.PubSub,
      AdaptorsSupervisor.client_topic(sup)
    )
  end

  @doc """
  Populates the catalogue from a JSON snapshot file. See
  `Lightning.Adaptors.Seed.seed_from_file/2`.
  """
  defdelegate seed_from_file(path, opts \\ []), to: Lightning.Adaptors.Seed
end
