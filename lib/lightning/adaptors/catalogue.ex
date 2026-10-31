defmodule Lightning.Adaptors.Catalogue do
  @moduledoc """
  Reads and writes for the `adaptors` and `adaptor_versions` tables.

  Every read takes the `:source` (`:npm | :local`) explicitly.
  `upsert_adaptor/1` is idempotent: `checked_at` advances on every call,
  `updated_at` only when a field actually changed, and version rows are
  replaced in the same transaction.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Adaptors.Catalogue.Adaptor
  alias Lightning.Adaptors.Catalogue.AdaptorVersion
  alias Lightning.Repo

  require Logger

  @type source :: :npm | :local

  @type package_meta :: %{
          name: String.t(),
          latest_version: String.t(),
          description: String.t() | nil,
          deprecated: boolean(),
          icon_square_ext: String.t() | nil,
          icon_rectangle_ext: String.t() | nil,
          icon_square_sha256: binary() | nil,
          icon_rectangle_sha256: binary() | nil,
          has_schema: boolean()
        }

  @type catalogue_entry :: %{
          name: String.t(),
          latest_version: String.t(),
          repository: String.t() | nil,
          versions: [String.t()],
          icon_square_ext: String.t() | nil,
          icon_rectangle_ext: String.t() | nil,
          icon_square_sha256: binary() | nil,
          icon_rectangle_sha256: binary() | nil
        }

  @version_row_fields ~w(adaptor_id version integrity tarball_url
                         size_bytes dependencies peer_dependencies
                         published_at deprecated)a

  # Packages that exist on npm but should never be offered in the picker.
  # Listing-only: `get_adaptor/2` still resolves them, so jobs already
  # using one keep validating.
  @excluded_names ~w(@openfn/language-devtools
                     @openfn/language-template
                     @openfn/language-fhir-jembi
                     @openfn/language-collections)

  @doc """
  Picker-facing lean projection for a source. Avoids the heavy
  `schema_data` JSONB column and skips the version join entirely.

  Excludes the packages listed in `@excluded_names` and any deprecated
  adaptor.
  """
  @spec list_package_metas(source()) :: [package_meta()]
  def list_package_metas(source) do
    source |> active_adaptors() |> select_package_meta() |> Repo.all()
  end

  @doc """
  The `t:package_meta/0` projection of one `(name, source)` row, or `nil`.
  Unlike `list_package_metas/1` this resolves excluded and deprecated
  adaptors too, so jobs already using one keep validating.
  """
  @spec get_package_meta(String.t(), source()) :: package_meta() | nil
  def get_package_meta(name, source) do
    from(a in Adaptor, where: a.name == ^name and a.source == ^source)
    |> select_package_meta()
    |> Repo.one()
  end

  defp select_package_meta(query) do
    from a in query,
      select: %{
        name: a.name,
        latest_version: a.latest_version,
        description: a.description,
        deprecated: a.deprecated,
        icon_square_ext: a.icon_square_ext,
        icon_rectangle_ext: a.icon_rectangle_ext,
        icon_square_sha256: a.icon_square_sha256,
        icon_rectangle_sha256: a.icon_rectangle_sha256,
        has_schema: not is_nil(a.schema_data)
      }
  end

  @doc """
  Full structs for a source, for callers that need the whole row, such as
  the Scheduler's diffing and the dump/seed tooling. Picker traffic uses
  the lighter `list_package_metas/1`.
  """
  @spec list_adaptors(source()) :: [Adaptor.t()]
  def list_adaptors(source) do
    Repo.all(from a in Adaptor, where: a.source == ^source)
  end

  @doc """
  Fetch a single adaptor by `name` within a `source`. Returns `nil`
  when no row matches.
  """
  @spec get_adaptor(String.t(), source()) :: Adaptor.t() | nil
  def get_adaptor(name, source) do
    Repo.get_by(Adaptor, name: name, source: source)
  end

  @doc """
  All versions of an adaptor (`name`, `source`), in insertion order.
  """
  @spec list_versions(String.t(), source()) :: [AdaptorVersion.t()]
  def list_versions(name, source) do
    Repo.all(
      from v in AdaptorVersion,
        join: a in Adaptor,
        on: v.adaptor_id == a.id,
        where: a.name == ^name and a.source == ^source,
        order_by: [asc: v.inserted_at]
    )
  end

  @doc """
  Upserts one adaptor record plus its version rows in one transaction.
  The source is read from the record, whose keys may be atoms or strings,
  as a decoded JSON snapshot gives them.

  `checked_at` advances on every call. `updated_at` advances only when
  some other field of the adaptor row differs from the existing row.
  Version rows are deleted and reinserted. Every row goes through its
  schema changeset first, so a corrupt strategy response cannot reach
  the database.

  Raises if the transaction fails, for example on invalid input from a
  misbehaving strategy. The Scheduler relies on the success type only.
  """
  @spec upsert_adaptor(map()) :: {:ok, Adaptor.t()}
  def upsert_adaptor(record) when is_map(record) do
    now = DateTime.utc_now()

    {versions, adaptor_attrs} =
      record
      |> stringify_keys()
      |> Map.put("checked_at", now)
      |> Map.pop("versions", [])

    name = Map.fetch!(adaptor_attrs, "name")
    source = adaptor_attrs |> Map.fetch!("source") |> normalize_source()

    multi =
      Multi.new()
      |> Multi.run(:existing, fn repo, _ ->
        {:ok, repo.get_by(Adaptor, name: name, source: source)}
      end)
      |> Multi.run(:adaptor, fn repo, %{existing: existing} ->
        upsert_adaptor_row(repo, existing, adaptor_attrs, now)
      end)
      |> Multi.run(:delete_versions, fn repo, %{adaptor: adaptor} ->
        {count, _} =
          repo.delete_all(
            from v in AdaptorVersion, where: v.adaptor_id == ^adaptor.id
          )

        {:ok, count}
      end)
      |> Multi.run(:insert_versions, fn repo, %{adaptor: adaptor} ->
        insert_version_rows(repo, adaptor.id, versions, now)
      end)

    case Repo.transaction(multi) do
      {:ok, %{adaptor: adaptor}} ->
        {:ok, adaptor}

      {:error, step, reason, _changes} ->
        raise ArgumentError,
              "Lightning.Adaptors.Catalogue.upsert_adaptor/1 failed at #{inspect(step)}: " <>
                inspect(reason)
    end
  end

  @doc """
  Delete every row for `source`.
  """
  @spec delete_all_for_source(source()) :: :ok
  def delete_all_for_source(source) do
    Repo.delete_all(from a in Adaptor, where: a.source == ^source)
    :ok
  end

  @doc """
  Advance `checked_at` for a known `(name, source)` row without
  loading it. No-op when no row matches.

  The Scheduler uses this when a poll finds nothing changed. It is
  cheaper than a full upsert and never bumps `updated_at`.
  """
  @spec touch_checked_at(String.t(), source()) :: :ok
  def touch_checked_at(name, source) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(a in Adaptor, where: a.name == ^name and a.source == ^source),
      set: [checked_at: now]
    )

    :ok
  end

  @doc """
  Update only the icon columns for a single `(name, source)` row.

  `attrs` may include any subset of `:icon_square_ext`,
  `:icon_square_sha256`, `:icon_rectangle_ext`, `:icon_rectangle_sha256`,
  `:icon_square_etag`, `:icon_rectangle_etag`.
  `updated_at` is advanced so callers can observe the change.

  Sidesteps `upsert_adaptor/1` deliberately: that helper rewrites the
  `adaptor_versions` rows in the same transaction, which is the wrong
  thing to do for an icon-only fix-up.
  """
  @spec update_icons(String.t(), source(), map()) :: {integer(), nil}
  def update_icons(name, source, attrs) when is_map(attrs) do
    allowed =
      attrs
      |> Map.take([
        :icon_square_ext,
        :icon_square_sha256,
        :icon_rectangle_ext,
        :icon_rectangle_sha256,
        :icon_square_etag,
        :icon_rectangle_etag
      ])
      |> Map.put(:updated_at, DateTime.utc_now())
      |> Enum.into([])

    Repo.update_all(
      from(a in Adaptor, where: a.name == ^name and a.source == ^source),
      set: allowed
    )
  end

  @doc """
  Maximum `checked_at` seen for `source`, or `nil` when the table is
  empty for that source. The Scheduler reads it at boot to time its first
  tick, and the Store reads it to tell whether the catalogue has ever
  loaded.
  """
  @spec max_checked_at(source()) :: DateTime.t() | nil
  def max_checked_at(source) do
    Repo.one(
      from a in Adaptor,
        where: a.source == ^source,
        select: max(a.checked_at)
    )
  end

  @doc """
  Full catalogue projection for a source: every adaptor's `name`,
  `latest_version`, `repository`, icon fields, and full version list.

  Excludes the packages listed in `@excluded_names` and any deprecated
  adaptor. A listed adaptor's deprecated versions are left out too.
  """
  @spec catalogue(source()) :: [catalogue_entry()]
  def catalogue(source) do
    adaptors =
      Repo.all(
        from a in active_adaptors(source),
          order_by: [asc: a.name],
          select: %{
            name: a.name,
            latest_version: a.latest_version,
            repository: a.repository,
            icon_square_ext: a.icon_square_ext,
            icon_rectangle_ext: a.icon_rectangle_ext,
            icon_square_sha256: a.icon_square_sha256,
            icon_rectangle_sha256: a.icon_rectangle_sha256
          }
      )

    versions_by_name =
      Repo.all(
        from v in AdaptorVersion,
          join: a in subquery(active_adaptors(source)),
          on: v.adaptor_id == a.id,
          where: v.deprecated == false,
          order_by: [asc: v.inserted_at, asc: v.version],
          select: {a.name, v.version}
      )
      |> Enum.group_by(fn {name, _version} -> name end, fn {_name, version} ->
        version
      end)

    Enum.map(adaptors, fn adaptor ->
      Map.put(adaptor, :versions, Map.get(versions_by_name, adaptor.name, []))
    end)
  end

  @doc """
  ETag basis for the catalogue: `{timestamp, version_row_count}` for
  `source`, where `timestamp` is the later of
  `MAX(adaptors.updated_at)` and `MAX(adaptor_versions.inserted_at)`,
  or `nil` when the source has no rows.

  `version_row_count` rides alongside the timestamp because deleting a
  version row moves neither max. It does lower the count.
  """
  @spec catalogue_stamp(source()) :: {DateTime.t() | nil, non_neg_integer()}
  def catalogue_stamp(source) do
    Repo.one(
      from a in Adaptor,
        left_join: v in AdaptorVersion,
        on: v.adaptor_id == a.id,
        where: a.source == ^source,
        select:
          {type(
             fragment("GREATEST(?, ?)", max(a.updated_at), max(v.inserted_at)),
             :utc_datetime_usec
           ), count(v.id)}
    )
  end

  # The adaptor-level predicate shared by every listing query: never a
  # hard-excluded name, never a deprecated adaptor. Resolve paths
  # (`get_adaptor/2`, `list_versions/2`) deliberately skip this.
  defp active_adaptors(source) do
    from a in Adaptor,
      where:
        a.source == ^source and a.name not in ^@excluded_names and
          a.deprecated == false
  end

  defp upsert_adaptor_row(repo, nil, attrs, _now) do
    %Adaptor{}
    |> Adaptor.changeset(attrs)
    |> repo.insert()
  end

  defp upsert_adaptor_row(repo, %Adaptor{} = existing, attrs, now) do
    changeset = Adaptor.changeset(existing, attrs)

    # `checked_at` changes on every call, so it is excluded from the diff.
    meaningful_changes? =
      changeset.changes
      |> Map.delete(:checked_at)
      |> map_size() > 0

    if meaningful_changes? do
      repo.update(changeset)
    else
      {1, _} =
        repo.update_all(
          from(a in Adaptor, where: a.id == ^existing.id),
          set: [checked_at: now]
        )

      {:ok, %{existing | checked_at: now}}
    end
  end

  defp insert_version_rows(_repo, _adaptor_id, [], _now), do: {:ok, 0}

  defp insert_version_rows(repo, adaptor_id, records, now) do
    case build_version_rows(adaptor_id, records, now) do
      {:ok, rows} ->
        {count, _} = repo.insert_all(AdaptorVersion, rows)
        {:ok, count}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp build_version_rows(adaptor_id, records, now) do
    records
    |> Enum.map(&stringify_keys/1)
    |> warn_duplicate_versions(adaptor_id)
    |> Enum.uniq_by(&Map.get(&1, "version"))
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, acc} ->
      attrs = Map.put(record, "adaptor_id", adaptor_id)

      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      if changeset.valid? do
        {:cont, {:ok, [version_row_from_changeset(changeset, now) | acc]}}
      else
        {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      err -> err
    end
  end

  defp warn_duplicate_versions(records, adaptor_id) do
    duplicated =
      records
      |> Enum.frequencies_by(&Map.get(&1, "version"))
      |> Enum.filter(fn {_version, count} -> count > 1 end)
      |> Enum.map(fn {version, _count} -> version end)

    if duplicated != [] do
      Logger.warning(
        "Lightning.Adaptors.Catalogue: duplicate version row(s) for adaptor " <>
          "#{inspect(adaptor_id)}, first occurrence wins: " <>
          Enum.join(duplicated, ", ")
      )
    end

    records
  end

  # `Ecto.Changeset.cast/3` raises on a map mixing atom and string keys, so
  # every map handed to a changeset here is flattened to string keys first.
  # A JSON snapshot arrives that way already.
  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  # `source` is read outside the changeset for the existing-row lookup, so
  # it needs its own cast. `Ecto.Enum` fields accept a string through
  # `Changeset.cast/3` but not through `Repo.get_by/3` query parameters.
  defp normalize_source(source) when is_atom(source), do: source

  defp normalize_source(source) when is_binary(source),
    do: String.to_existing_atom(source)

  defp version_row_from_changeset(changeset, now) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take(@version_row_fields)
    |> Map.put(:id, Ecto.UUID.generate())
    |> Map.put(:inserted_at, now)
  end
end
