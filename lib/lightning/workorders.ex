defmodule Lightning.Workorders do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Lightning.Repo

  @doc """
  Get a map of counts for successful, rerun and failed Workorders for a given
  digest.
  """
  def get_digest_data(workflow, digest)
      when digest in [:daily, :weekly, :monthly] do
    %{
      workflow_name: workflow.name,
      successful_workorders:
        successful_workorders_query(workflow, digest) |> Repo.one(),
      rerun_workorders: rerun_workorders_query(workflow, digest) |> Repo.one(),
      failed_workorders: failed_workorders_query(workflow, digest) |> Repo.one()
    }
  end

  defp filter_digest(digest) do
    from_date =
      case digest do
        :monthly ->
          Timex.now() |> Timex.shift(months: -1) |> Timex.beginning_of_month()

        :daily ->
          Timex.now() |> Timex.beginning_of_day()

        :weekly ->
          Timex.now() |> Timex.shift(days: -7) |> Timex.beginning_of_week()
      end

    dynamic([r], r.finished_at >= ^from_date)
  end

  defp successful_workorders_query(workflow, digest) do
    from(wo in Lightning.WorkOrder,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      join: att in assoc(wo, :attempts),
      on: wo.id == att.work_order_id,
      join: r in assoc(att, :runs),
      as: :runs,
      join:
        run in subquery(
          from(r in Lightning.Invocation.Run,
            join: att in assoc(r, :attempts),
            group_by: [att.id, r.exit_code],
            where: r.exit_code == 0,
            where: ^filter_digest(digest),
            select: %{
              attempt_id: att.id
            }
          )
        ),
      on: att.id == run.attempt_id,
      where: w.id == ^workflow.id,
      select: count(w.id)
    )
  end

  defp rerun_workorders_query(workflow, digest) do
    from(
      attempt in Lightning.Attempt,
      as: :attempts,
      where:
        1 <
          subquery(
            from(wo in Lightning.WorkOrder,
              join: w in assoc(wo, :workflow),
              as: :workflow,
              join: att in assoc(wo, :attempts),
              on: wo.id == att.work_order_id,
              join: r in assoc(att, :runs),
              as: :runs,
              join:
                run in subquery(
                  from(r in Lightning.Invocation.Run,
                    join: att in assoc(r, :attempts),
                    group_by: [att.id, r.exit_code],
                    where: r.exit_code == 0,
                    where: ^filter_digest(digest),
                    select: %{
                      attempt_id: att.id
                    }
                  )
                ),
              on: att.id == run.attempt_id,
              where: w.id == ^workflow.id,
              where: parent_as(:attempts).work_order_id == wo.id,
              select: count(wo.id)
            )
          ),
      select: count(attempt.id)
    )
  end

  defp failed_workorders_query(workflow, digest) do
    from(wo in Lightning.WorkOrder,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      join: att in assoc(wo, :attempts),
      on: wo.id == att.work_order_id,
      join: r in assoc(att, :runs),
      as: :runs,
      join:
        run in subquery(
          from(r in Lightning.Invocation.Run,
            join: att in assoc(r, :attempts),
            group_by: [att.id, r.exit_code],
            where: r.exit_code != 0,
            where: ^filter_digest(digest),
            select: %{
              attempt_id: att.id
            }
          )
        ),
      on: att.id == run.attempt_id,
      where: w.id == ^workflow.id,
      select: count(w.id)
    )
  end
end
