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

  alias Lightning.Repo
  alias Lightning.WorkOrder
  alias Lightning.Attempt

  import Ecto.Query

  # @doc """
  # Create a new Workorder.

  # A workorder request
  # """

  def create(workflow, opts) do
    trigger = Keyword.get(opts, :trigger)
    dataclip = Keyword.get(opts, :dataclip)

    Repo.all(Lightning.Workflows.Node) |> IO.inspect()

    workflow_node_id = from(n in Lightning.Workflows.Node,
      where: n.workflow_id == ^workflow.id and n.trigger_id == ^trigger.id,
      select: n.id
    )
    |> Repo.one()
    |> IO.inspect()

    %WorkOrder{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:workflow, workflow)
    |> Ecto.Changeset.put_assoc(:trigger, trigger)
    |> Ecto.Changeset.put_assoc(:dataclip, dataclip)
    |> Ecto.Changeset.put_assoc(:attempts, [%Attempt{starting_node_id: workflow_node_id}])
    |> Ecto.Changeset.validate_required([:workflow, :trigger, :dataclip])
    |> Ecto.Changeset.assoc_constraint(:workflow)
    |> Repo.insert()
  end

  # defp build(workflow, trigger) do
  #   WorkOrder.changeset(%WorkOrder{}, %{})
  #   |> Ecto.Changeset.put_assoc(:workflow, workflow)

  # end
end
