defmodule Lightning.Adaptors.Repo do
  @moduledoc """
  Query and write helpers over the `adaptors` and `adaptor_versions` tables.

  Despite the name, this is **not** an `Ecto.Repo` — it is a thin
  data-access module that wraps `Lightning.Repo` (the real
  `Ecto.Repo`). The two schemas it targets live as siblings:
  `Lightning.Adaptors.Repo.Adaptor` and
  `Lightning.Adaptors.Repo.AdaptorVersion`.

  Every read helper takes the desired `:source` (`:npm | :local`)
  explicitly; the module itself stays source-agnostic. Callers resolve
  the active source via `Lightning.Adaptors.Config.current_source/0`
  (see §4.4 source-tagging invariant and §6.4 in
  `.context/lightning/adaptors/REWRITE-2026-05.md`).

  `upsert_adaptor/1` is the only writer the Scheduler uses. It is
  idempotent, transactional, and diff-aware: `checked_at` advances on
  every call, while `updated_at` only advances when the row's
  meaningful fields differ from what was already in the DB. Version
  rows are replaced inside the same transaction so a partial failure
  cannot leave the table half-rewritten.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Adaptors.Repo.Adaptor
  alias Lightning.Adaptors.Repo.AdaptorVersion

  @type source :: :npm | :local

  @type package_meta :: %{
          name: String.t(),
          latest_version: String.t(),
          description: String.t() | nil,
          deprecated: boolean(),
          updated_at: DateTime.t(),
          icon_square_ext: String.t() | nil,
          icon_rectangle_ext: String.t() | nil,
          icon_square_sha256: binary() | nil,
          icon_rectangle_sha256: binary() | nil
        }

  @version_row_fields ~w(adaptor_id version integrity tarball_url
                         size_bytes dependencies peer_dependencies
                         published_at deprecated)a

  @doc """
  Picker-facing lean projection for a source. Avoids the heavy JSONB
  columns (`schema_data`, `dependencies`, `peer_dependencies`).
  """
  @spec list_package_metas(source()) :: [package_meta()]
  def list_package_metas(source) do
    Lightning.Repo.all(
      from a in Adaptor,
        where: a.source == ^source,
        select: %{
          name: a.name,
          latest_version: a.latest_version,
          description: a.description,
          deprecated: a.deprecated,
          updated_at: a.updated_at,
          icon_square_ext: a.icon_square_ext,
          icon_rectangle_ext: a.icon_rectangle_ext,
          icon_square_sha256: a.icon_square_sha256,
          icon_rectangle_sha256: a.icon_rectangle_sha256
        }
    )
  end

  @doc """
  Full structs for a source. Rare — used by debug tools and admin
  views. Picker traffic goes through `list_package_metas/1`.
  """
  @spec list_adaptors(source()) :: [Adaptor.t()]
  def list_adaptors(source) do
    Lightning.Repo.all(from a in Adaptor, where: a.source == ^source)
  end

  @doc """
  Fetch a single adaptor by `name` within a `source`. Returns `nil`
  when no row matches.
  """
  @spec get_adaptor(String.t(), source()) :: Adaptor.t() | nil
  def get_adaptor(name, source) do
    Lightning.Repo.get_by(Adaptor, name: name, source: source)
  end

  @doc """
  All versions of an adaptor (`name`, `source`), in insertion order.
  """
  @spec list_versions(String.t(), source()) :: [AdaptorVersion.t()]
  def list_versions(name, source) do
    Lightning.Repo.all(
      from v in AdaptorVersion,
        join: a in Adaptor,
        on: v.adaptor_id == a.id,
        where: a.name == ^name and a.source == ^source,
        order_by: [asc: v.inserted_at]
    )
  end

  @doc """
  Idempotent, transactional, diff-aware upsert of one adaptor record
  plus its version rows. The `:source` is read from the record.

  Behaviour:

    * On every call, `checked_at` is advanced to "now".
    * `updated_at` only advances when at least one non-`checked_at`
      field of the adaptor row actually differs from the existing row.
    * Version rows are replaced (delete + insert) inside the same
      transaction.
    * Every row is run through its schema changeset before write, so a
      corrupt Strategy response cannot poison the DB.

  Raises if the underlying transaction fails (e.g. invalid input from
  a misbehaving strategy) — the success type is the only contract the
  Scheduler relies on.
  """
  @spec upsert_adaptor(map()) :: {:ok, Adaptor.t()}
  def upsert_adaptor(record) when is_map(record) do
    now = DateTime.utc_now()

    {versions, adaptor_attrs} =
      record
      |> Map.put(:checked_at, now)
      |> Map.pop(:versions, [])

    name = Map.fetch!(adaptor_attrs, :name)
    source = Map.fetch!(adaptor_attrs, :source)

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

    case Lightning.Repo.transaction(multi) do
      {:ok, %{adaptor: adaptor}} ->
        {:ok, adaptor}

      {:error, step, reason, _changes} ->
        raise ArgumentError,
              "Lightning.Adaptors.Repo.upsert_adaptor/1 failed at #{inspect(step)}: " <>
                inspect(reason)
    end
  end

  @doc """
  Advance `checked_at` for a known `(name, source)` row without
  loading it. No-op when no row matches.

  Used by the Scheduler's "polled NPM, nothing changed" path —
  cheaper than a full upsert and never bumps `updated_at`.
  """
  @spec touch_checked_at(String.t(), source()) :: :ok
  def touch_checked_at(name, source) do
    now = DateTime.utc_now()

    Lightning.Repo.update_all(
      from(a in Adaptor, where: a.name == ^name and a.source == ^source),
      set: [checked_at: now]
    )

    :ok
  end

  @doc """
  The `limit` rows for a given `source` whose `checked_at` is oldest
  first. Backs the Scheduler's per-tick work list.
  """
  @spec stalest(pos_integer(), source()) :: [Adaptor.t()]
  def stalest(limit, source) when is_integer(limit) and limit > 0 do
    Lightning.Repo.all(
      from a in Adaptor,
        where: a.source == ^source,
        order_by: [asc: a.checked_at],
        limit: ^limit
    )
  end

  @doc """
  Lean list of source-scoped adaptors that are missing at least one icon
  shape. Returns only the fields the Scheduler needs to decide whether to
  re-apply the bulk icon fetch result.
  """
  @spec list_missing_icons(source()) :: [
          %{
            name: String.t(),
            icon_square_sha256: binary() | nil,
            icon_rectangle_sha256: binary() | nil
          }
        ]
  def list_missing_icons(source) do
    Lightning.Repo.all(
      from a in Adaptor,
        where:
          a.source == ^source and
            (is_nil(a.icon_square_sha256) or is_nil(a.icon_rectangle_sha256)),
        select: %{
          name: a.name,
          icon_square_sha256: a.icon_square_sha256,
          icon_rectangle_sha256: a.icon_rectangle_sha256
        }
    )
  end

  @doc """
  Update only the icon columns for a single `(name, source)` row.

  `attrs` may include any subset of `:icon_square_ext`,
  `:icon_square_sha256`, `:icon_rectangle_ext`, `:icon_rectangle_sha256`.
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
        :icon_rectangle_sha256
      ])
      |> Map.put(:updated_at, DateTime.utc_now())
      |> Enum.into([])

    Lightning.Repo.update_all(
      from(a in Adaptor, where: a.name == ^name and a.source == ^source),
      set: allowed
    )
  end

  @doc """
  Maximum `checked_at` seen for `source`, or `nil` when the table is
  empty for that source. Backs the Scheduler's smart-init timing.
  """
  @spec max_checked_at(source()) :: DateTime.t() | nil
  def max_checked_at(source) do
    Lightning.Repo.one(
      from a in Adaptor,
        where: a.source == ^source,
        select: max(a.checked_at)
    )
  end

  defp upsert_adaptor_row(repo, nil, attrs, _now) do
    %Adaptor{}
    |> Adaptor.changeset(attrs)
    |> repo.insert()
  end

  defp upsert_adaptor_row(repo, %Adaptor{} = existing, attrs, now) do
    changeset = Adaptor.changeset(existing, attrs)

    # `Ecto.Changeset.cast/3` only records a change when the cast value
    # differs from the underlying struct, so the set of "real" changes
    # is `:changes` minus the `:checked_at` tick we apply on every call.
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
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, acc} ->
      attrs = Map.put(record, :adaptor_id, adaptor_id)
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

  defp version_row_from_changeset(changeset, now) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take(@version_row_fields)
    |> Map.put(:id, Ecto.UUID.generate())
    |> Map.put(:inserted_at, now)
  end
end
