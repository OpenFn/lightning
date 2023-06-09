defmodule Lightning.Factories do
  @spec build(atom(), keyword()) :: struct() | map() | no_return()
  def build(f, attrs \\ [])

  def build(:job, attrs) do
    struct!(Lightning.Jobs.Job, %{
      workflow: build(:workflow),
      trigger: build(:trigger)
    })
    |> merge_attributes(attrs)
  end

  def build(:trigger, attrs) do
    struct!(Lightning.Jobs.Trigger, %{workflow: build(:workflow)})
    |> merge_attributes(attrs)
  end

  def build(:edge, attrs) do
    struct!(Lightning.Workflows.Edge, %{workflow: build(:workflow)})
    |> merge_attributes(attrs)
  end

  def build(:dataclip, attrs) do
    struct!(Lightning.Invocation.Dataclip, %{project: build(:project)})
    |> merge_attributes(attrs)
  end

  def build(:user, attrs) do
    struct!(Lightning.Accounts.User, %{
      email: "user#{System.unique_integer()}@example.com",
      password: "hello world!",
      first_name: "anna",
      hashed_password: Bcrypt.hash_pwd_salt("hello world!")
    })
    |> merge_attributes(attrs)
  end

  def build(:run, attrs) do
    struct!(Lightning.Invocation.Run, %{
      job: build(:job),
      input_dataclip: build(:dataclip)
    })
    |> merge_attributes(attrs)
  end

  def build(:attempt, attrs) do
    struct!(Lightning.Attempt, attrs)
  end

  def build(:reason, attrs) do
    struct!(Lightning.InvocationReason, attrs)
  end

  def build(:workorder, attrs) do
    struct!(
      Lightning.WorkOrder,
      %{workflow: build(:workflow)}
    )
    |> merge_attributes(attrs)
  end

  def build(:workflow, attrs) do
    struct!(Lightning.Workflows.Workflow, %{project: build(:project)})
    |> merge_attributes(attrs)
  end

  def build(:edge, attrs) do
    struct!(Lightning.Workflows.Edge, attrs)
  end

  def build(:project, attrs) do
    struct!(Lightning.Projects.Project, attrs)
  end


  def insert(%{__struct__: struct} = record) do
    Ecto.Changeset.change(struct!(struct))
    |> put_fields(record)
    |> put_assocs(record)
    |> Lightning.Repo.insert!()
  end

  def insert(f) when is_atom(f) do
    build(f, []) |> insert()
  end

  def insert(f, attrs) when is_atom(f) do
    build(f, attrs) |> insert()
  end

  @spec merge_attributes(struct | map, map) :: struct | map | no_return
  def merge_attributes(%{__struct__: _} = record, attrs),
    do: struct!(record, attrs)

  def merge_attributes(record, attrs), do: Map.merge(record, attrs)

  defp put_assocs(changeset, %{__struct__: struct} = record) do
    struct.__schema__(:associations)
    |> Enum.reduce(changeset, fn association_name, changeset ->
      case Map.get(record, association_name) do
        %Ecto.Association.NotLoaded{} ->
          changeset

        value ->
          Ecto.Changeset.put_assoc(changeset, association_name, value)
      end
    end)
  end

  defp put_fields(changeset, %{__struct__: struct} = record) do
    struct.__schema__(:fields)
    |> Enum.reduce(changeset, fn field_name, changeset ->
      Ecto.Changeset.put_change(
        changeset,
        field_name,
        Map.get(record, field_name)
      )
    end)
  end
end
