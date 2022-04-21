defmodule Lightning.Invocation do
  @moduledoc """
  The Invocation context.
  """

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]
  alias Lightning.Repo

  alias Lightning.Invocation.{Dataclip, Event, Run}
  alias Ecto.Multi

  @doc """
  Create a new invocation based on a job and a body of data, which gets saved
  as a Dataclip; resulting in a Run associated with the Event.
  """
  @spec create(
          %{job_id: binary(), type: :webhook},
          %{type: :http_request, body: map()}
        ) :: {:ok | :error, any}
  def create(event_attrs, dataclip_attrs) do
    Multi.new()
    |> Multi.insert(:dataclip, Dataclip.changeset(%Dataclip{}, dataclip_attrs))
    |> Multi.insert(:event, fn %{dataclip: %Dataclip{id: dataclip_id}} ->
      Event.changeset(%Event{}, event_attrs)
      |> Event.changeset(%{dataclip_id: dataclip_id})
    end)
    |> Multi.insert(:run, fn %{event: %Event{id: event_id}} ->
      Run.changeset(%Run{}, %{event_id: event_id})
    end)
    |> Repo.transaction()
  end

  @doc """
  Returns the list of dataclips.

  ## Examples

      iex> list_dataclips()
      [%Dataclip{}, ...]

  """
  def list_dataclips do
    Repo.all(Dataclip)
  end

  @doc """
  Gets a single dataclip.

  Raises `Ecto.NoResultsError` if the Dataclip does not exist.

  ## Examples

      iex> get_dataclip!(123)
      %Dataclip{}

      iex> get_dataclip!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_dataclip!(id :: Ecto.UUID.t()) :: Dataclip.t()
  def get_dataclip!(id), do: Repo.get!(Dataclip, id)

  @doc """
  Gets a single dataclip given one of:

  - a Dataclip uuid
  - a Run model, that has an associated dataclip via it's event

  Returns `nil` if the Dataclip does not exist.

  ## Examples

      iex> get_dataclip("27b73932-16c7-4a72-86a3-85d805ccff98")
      %Dataclip{}

      iex> get_dataclip("27b73932-16c7-4a72-86a3-85d805ccff98")
      nil

      iex> get_dataclip(%Run{id: "a uuid"})
      %Dataclip{}

  """
  @spec get_dataclip(run_or_uuid :: Run.t() | Ecto.UUID.t()) :: Dataclip.t() | nil
  def get_dataclip(%Run{id: id}) do
    from(r in Run, join: d in assoc(r, :dataclip), select: d, where: r.id == ^id)
    |> Repo.one()
  end

  def get_dataclip(id), do: Repo.get(Dataclip, id)

  @doc """
  Gets a single dataclip's body as a string
  Returns `nil` if the Dataclip does not exist.
  """
  @spec get_dataclip_body(Run.t()) :: String.t() | nil
  def get_dataclip_body(%Run{id: id}) do
    from(r in Run,
      join: d in assoc(r, :dataclip),
      select: type(d.body, :string),
      where: r.id == ^id
    )
    |> Repo.one()
  end

  @doc """
  Creates a dataclip.

  ## Examples

      iex> create_dataclip(%{field: value})
      {:ok, %Dataclip{}}

      iex> create_dataclip(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_dataclip(attrs :: map()) ::
          {:ok, Dataclip.t()} | {:error, Ecto.Changeset.t(Dataclip)}
  def create_dataclip(attrs \\ %{}) do
    %Dataclip{}
    |> Dataclip.changeset(attrs |> coerce_json_field("body"))
    |> Repo.insert()
  end

  @doc """
  Updates a dataclip.

  ## Examples

      iex> update_dataclip(dataclip, %{field: new_value})
      {:ok, %Dataclip{}}

      iex> update_dataclip(dataclip, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_dataclip(%Dataclip{} = dataclip, attrs) do
    dataclip
    |> Dataclip.changeset(attrs |> coerce_json_field("body"))
    |> Repo.update()
  end

  @doc """
  Deletes a dataclip.

  ## Examples

      iex> delete_dataclip(dataclip)
      {:ok, %Dataclip{}}

      iex> delete_dataclip(dataclip)
      {:error, %Ecto.Changeset{}}

  """
  def delete_dataclip(%Dataclip{} = dataclip) do
    Repo.delete(dataclip)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking dataclip changes.

  ## Examples

      iex> change_dataclip(dataclip)
      %Ecto.Changeset{data: %Dataclip{}}

  """
  def change_dataclip(%Dataclip{} = dataclip, attrs \\ %{}) do
    Dataclip.changeset(dataclip, attrs |> coerce_json_field("body"))
  end

  @doc """
  Creates an event.

  ## Examples

      iex> create_event(%{type: :webhook, dataclip_id: dataclip.id})
      {:ok, %Dataclip{}}

      iex> create_dataclip(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the list of runs.

  ## Examples

      iex> list_runs()
      [%Run{}, ...]

  """
  def list_runs do
    Repo.all(Run)
  end

  @doc """
  Gets a single run.

  Raises `Ecto.NoResultsError` if the Run does not exist.

  ## Examples

      iex> get_run!(123)
      %Run{}

      iex> get_run!(456)
      ** (Ecto.NoResultsError)

  """
  def get_run!(id), do: Repo.get!(Run, id)

  @doc """
  Creates a run.

  ## Examples

      iex> create_run(%{field: value})
      {:ok, %Run{}}

      iex> create_run(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_run(attrs \\ %{}) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a run.

  ## Examples

      iex> update_run(run, %{field: new_value})
      {:ok, %Run{}}

      iex> update_run(run, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_run(%Run{} = run, attrs) do
    run
    |> Run.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a run.

  ## Examples

      iex> delete_run(run)
      {:ok, %Run{}}

      iex> delete_run(run)
      {:error, %Ecto.Changeset{}}

  """
  def delete_run(%Run{} = run) do
    Repo.delete(run)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking run changes.

  ## Examples

      iex> change_run(run)
      %Ecto.Changeset{data: %Run{}}

  """
  def change_run(%Run{} = run, attrs \\ %{}) do
    Run.changeset(run, attrs)
  end
end
