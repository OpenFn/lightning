defmodule Lightning.WorkOrders do
  @moduledoc """
  Context for creating Workorders.

  ## Workorders

  Workorders represent the entrypoint for a unit of work in Lightning.
  They allow you to track the status of a webhook or cron trigger.

  For example if a user makes a request to a webhook endpoint, a Workorder
  is created with it's associated Workflow and Dataclip.

  Every Workorder has at least one Attempt, which represents a single
  invocation of the Workflow. If the workflow fails, and the attempt is retried,
  a new Attempt is created on the Workorder.

  This allows you group all the attempts for a single webhook, and track
  the success or failure of a given dataclip.

  ## Creating Workorders

  Workorders can be created in three ways:

  1. Via a webhook trigger
  2. Via a cron trigger
  3. Manually by a user (via the UI or API)

  Retries do not create new Workorders, but rather new Attempts on the existing
  Workorder.
  """

  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Trigger
  alias Lightning.Repo
  alias Lightning.WorkOrder
  alias Lightning.Attempt

  import Ecto.Changeset
  import Lightning.Validators
  import Ecto.Query

  # @doc """
  # Create a new Workorder.
  #
  # **For a webhook**
  #     create(trigger, workflow: workflow, dataclip: dataclip)
  #
  # **For a user**
  #     create(job, workflow: workflow, dataclip: dataclip, user: user)
  # """
  def create_for(%Trigger{} = trigger, opts) do
    build_for(trigger, opts |> Map.new())
    |> Repo.insert()
  end

  def create_for(%Job{} = job, opts) do
    build_for(job, opts |> Map.new())
    |> Repo.insert()
  end

  def build_for(%Trigger{} = trigger, attrs) do
    %WorkOrder{}
    |> change()
    |> put_assoc(:workflow, attrs[:workflow])
    |> put_assoc(:trigger, trigger)
    |> put_assoc(:dataclip, attrs[:dataclip])
    |> put_assoc(:attempts, [
      Attempt.for(trigger, %{dataclip: attrs[:dataclip]})
    ])
    |> validate_required_assoc(:workflow)
    |> validate_required_assoc(:trigger)
    |> validate_required_assoc(:dataclip)
    |> assoc_constraint(:trigger)
    |> assoc_constraint(:workflow)
  end

  def build_for(%Job{} = job, attrs) do
    %WorkOrder{}
    |> change()
    |> put_assoc(:workflow, attrs[:workflow])
    |> put_assoc(:dataclip, attrs[:dataclip])
    |> put_assoc(:attempts, [
      Attempt.for(job, %{
        dataclip: attrs[:dataclip],
        created_by: attrs[:created_by]
      })
    ])
    |> validate_required_assoc(:workflow)
    |> validate_required_assoc(:dataclip)
    |> assoc_constraint(:trigger)
    |> assoc_constraint(:workflow)
  end

  def get(id, opts \\ []) do
    preloads = opts |> Keyword.get(:include, [])

    from(w in WorkOrder,
      where: w.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
  end
end
