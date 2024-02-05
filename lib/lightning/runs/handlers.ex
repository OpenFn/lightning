defmodule Lightning.Runs.Handlers do
  @moduledoc """
  Handler modules for working with runs.
  """

  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Runs
  alias Lightning.RunStep
  alias Lightning.WorkOrders

  defmodule StartStep do
    @moduledoc """
    Schema to validate the input attributes of a started step.
    """
    use Ecto.Schema
    import Ecto.Changeset
    import Ecto.Query

    @primary_key false
    embedded_schema do
      field :run_id, Ecto.UUID
      field :step_id, Ecto.UUID
      field :credential_id, Ecto.UUID
      field :job_id, Ecto.UUID
      field :input_dataclip_id, Ecto.UUID
      field :started_at, :utc_datetime_usec
    end

    def new(params) do
      cast(%__MODULE__{}, params, [
        :run_id,
        :step_id,
        :credential_id,
        :job_id,
        :input_dataclip_id,
        :started_at
      ])
      |> then(fn changeset ->
        if get_change(changeset, :started_at) do
          changeset
        else
          put_change(changeset, :started_at, DateTime.utc_now())
        end
      end)
      |> validate_required([
        :run_id,
        :step_id,
        :job_id,
        :started_at
      ])
      |> then(&validate_job_reachable/1)
    end

    def call(params) do
      with {:ok, attrs} <- new(params) |> apply_action(:validate),
           {:ok, step} <- insert(attrs) do
        run = Runs.get(attrs.run_id, include: [:workflow])
        WorkOrders.Events.run_updated(run.workflow.project_id, run)
        Runs.Events.step_started(attrs.run_id, step)

        {:ok, step}
      end
    end

    defp insert(attrs) do
      Repo.transact(fn ->
        with {:ok, step} <- attrs |> to_step() |> Repo.insert(),
             {:ok, _} <- attrs |> to_run_step() |> Repo.insert() do
          {:ok, step}
        end
      end)
    end

    defp to_step(%__MODULE__{step_id: step_id} = start_step) do
      start_step
      |> Map.take([:credential_id, :input_dataclip_id, :job_id, :started_at])
      |> Map.put(:id, step_id)
      |> Step.new()
    end

    defp to_run_step(%__MODULE__{step_id: step_id, run_id: run_id}) do
      RunStep.new(%{
        step_id: step_id,
        run_id: run_id
      })
    end

    defp validate_job_reachable(changeset) do
      case changeset do
        %{valid?: false} ->
          changeset

        _ ->
          job_id = get_field(changeset, :job_id)
          run_id = get_field(changeset, :run_id)

          # Verify that all of the required entities exist with a single query,
          # then reduce the results into a single changeset by adding errors for
          # any columns/ids that are null.
          run_id
          |> fetch_existing_job(job_id)
          |> Enum.reduce(changeset, fn {k, v}, changeset ->
            if is_nil(v) do
              add_error(changeset, k, "does not exist")
            else
              changeset
            end
          end)
      end
    end

    defp fetch_existing_job(run_id, job_id) do
      query =
        from(a in Run,
          where: a.id == ^run_id,
          left_join: w in assoc(a, :workflow),
          left_join: j in assoc(w, :jobs),
          on: j.id == ^job_id,
          select: %{run_id: a.id, job_id: j.id}
        )

      Repo.one(query) || %{run_id: nil, job_id: nil}
    end
  end

  defmodule CompleteStep do
    @moduledoc """
    Schema to validate the input attributes of a completed step.
    """
    use Ecto.Schema
    import Ecto.Changeset
    import Ecto.Query

    @primary_key false
    embedded_schema do
      field :project_id, Ecto.UUID
      field :run_id, Ecto.UUID
      field :output_dataclip, :string
      field :output_dataclip_id, Ecto.UUID
      field :reason, :string
      field :error_type, :string
      field :error_message, :string
      field :step_id, Ecto.UUID
      field :finished_at, :utc_datetime_usec
    end

    def new(params, retention_policy) do
      cast(%__MODULE__{}, params, [
        :run_id,
        :output_dataclip,
        :output_dataclip_id,
        :project_id,
        :reason,
        :error_type,
        :error_message,
        :step_id,
        :finished_at
      ])
      |> then(fn changeset ->
        if get_change(changeset, :finished_at) do
          changeset
        else
          put_change(changeset, :finished_at, DateTime.utc_now())
        end
      end)
      |> then(fn changeset ->
        output_dataclip_id = get_change(changeset, :output_dataclip_id)
        output_dataclip = get_change(changeset, :output_dataclip)

        case {retention_policy, output_dataclip, output_dataclip_id} do
          {:erase_all, _, _} ->
            changeset

          {_, nil, nil} ->
            changeset

          _ ->
            changeset
            |> validate_required([:output_dataclip, :output_dataclip_id])
        end
      end)
      |> validate_required([
        :run_id,
        :finished_at,
        :project_id,
        :reason,
        :step_id
      ])
    end

    def call(params, retention_policy) do
      with {:ok, complete_step} <-
             params |> new(retention_policy) |> apply_action(:validate),
           {:ok, step} <- update_step(complete_step, retention_policy) do
        Runs.Events.step_completed(complete_step.run_id, step)

        {:ok, step}
      end
    end

    defp update_step(complete_step, retention_policy) do
      Repo.transact(fn ->
        with %Step{} = step <- get_step(complete_step.step_id),
             {:ok, _} <- maybe_save_dataclip(complete_step, retention_policy) do
          step
          |> Step.finished(
            complete_step.output_dataclip_id,
            {complete_step.reason, complete_step.error_type,
             complete_step.error_message}
          )
          |> Repo.update()
        else
          nil ->
            {:error,
             complete_step
             |> change()
             |> add_error(:step_id, "not found")}

          error ->
            error
        end
      end)
    end

    defp get_step(id) do
      from(s in Lightning.Invocation.Step, where: s.id == ^id)
      |> Repo.one()
    end

    defp maybe_save_dataclip(
           %__MODULE__{
             project_id: project_id,
             output_dataclip_id: dataclip_id
           },
           :erase_all
         ) do
      if is_nil(dataclip_id) do
        {:ok, nil}
      else
        Dataclip.new(%{
          id: dataclip_id,
          project_id: project_id,
          body: nil,
          wiped_at: DateTime.utc_now() |> DateTime.truncate(:second),
          type: :step_result
        })
        |> Repo.insert()
      end
    end

    defp maybe_save_dataclip(
           %__MODULE__{output_dataclip: nil},
           _retention_policy
         ) do
      {:ok, nil}
    end

    defp maybe_save_dataclip(
           %__MODULE__{
             output_dataclip: output_dataclip,
             project_id: project_id,
             output_dataclip_id: dataclip_id
           },
           _retention_policy
         ) do
      Dataclip.new(%{
        id: dataclip_id,
        project_id: project_id,
        body: output_dataclip |> Jason.decode!(),
        type: :step_result
      })
      |> Repo.insert()
    end
  end
end
