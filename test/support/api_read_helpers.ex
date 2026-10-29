defmodule LightningWeb.ApiReadHelpers do
  @moduledoc """
  Builders for the API tests of the routes that list and show runs, work
  orders, log lines and jobs.
  """
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers, only: [not_a_uuid_entry: 1]
  import LightningWeb.ConnHelpers, only: [assign_bearer: 2]
  import Lightning.ServiceAccountHelpers, only: [with_service_account: 2]

  alias Lightning.Projects.Project

  @doc """
  Inserts a work order in `target`, a workflow or a project (which gets a new
  workflow). `attrs` go to the work order.
  """
  def insert_work_order(target, attrs \\ []) do
    workflow = workflow_for(target)

    trigger =
      Keyword.get_lazy(attrs, :trigger, fn ->
        insert(:trigger, workflow: workflow)
      end)

    insert(
      :workorder,
      Keyword.merge(
        [workflow: workflow, trigger: trigger, dataclip: build(:dataclip)],
        attrs
      )
    )
  end

  @doc """
  Inserts a work order holding one run, in `target`, and returns the run.
  `run_attrs` go to the run, `work_order_attrs` to the work order, which takes
  the run's `inserted_at` unless it is given its own.
  """
  def insert_run(target, run_attrs \\ [], work_order_attrs \\ []) do
    workflow = workflow_for(target)
    trigger = insert(:trigger, workflow: workflow)

    run =
      Map.merge(
        %{
          state: :started,
          dataclip: build(:dataclip),
          starting_trigger: trigger
        },
        Map.new(run_attrs)
      )

    inserted =
      for {:inserted_at, at} <- Map.to_list(run), do: {:inserted_at, at}

    %{runs: [run]} =
      insert_work_order(
        workflow,
        Keyword.merge(
          [trigger: trigger, runs: [run]] ++ inserted,
          work_order_attrs
        )
      )

    run
  end

  defp workflow_for(%Project{} = project),
    do: insert(:workflow, project: project)

  defp workflow_for(workflow), do: workflow

  @doc """
  The rows of the "who may reach it" table for reading `kind` on its own
  routes and under a project, each `{caller, path, status, code, entries}` for
  `assert_problem/4`.

  `member` is a conn bearing the token of a member of `project`, and `insert`
  puts a record of the kind in the project it is given and returns it.
  """
  def who_may_read(member, project, kind, insert)
      when kind in ~w(jobs runs work_orders workflows) do
    own = insert.(project)
    stranger = assign_bearer(member, insert(:user))
    superuser = assign_bearer(member, insert(:user, role: :superuser))

    {service_account, _account} =
      with_service_account(member, ["projects:write"])

    short_of_mfa = insert(:user)

    guarded =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: short_of_mfa}]
      )

    short_of_mfa = assign_bearer(member, short_of_mfa)
    guarded_one = insert.(guarded)
    elsewhere = insert.(insert(:project))
    unknown = Ecto.UUID.generate()
    top = "/api/#{kind}"
    nested = fn project_id -> "/api/projects/#{project_id}/#{kind}" end

    path_id = [not_a_uuid_entry(%{"path" => "id"})]
    path_project_id = [not_a_uuid_entry(%{"path" => "project_id"})]

    query_project_id = [
      not_a_uuid_entry(%{"parameter" => "project_id"})
    ]

    [
      {stranger, "#{top}/#{own.id}", 403, :forbidden, []},
      {stranger, "#{top}/#{unknown}", 403, :forbidden, []},
      {stranger, "#{top}/not-a-uuid", 403, :forbidden, []},
      {stranger, "#{nested.(project.id)}/#{own.id}", 403, :forbidden, []},
      {stranger, "#{nested.(project.id)}/#{unknown}", 403, :forbidden, []},
      {stranger, "#{nested.(project.id)}/not-a-uuid", 403, :forbidden, []},
      {stranger, "#{nested.(project.id)}?state=sideways", 403, :forbidden, []},
      {stranger, "#{top}?project_id=#{project.id}", 403, :forbidden, []},
      {stranger, "#{top}?project_id=not-a-uuid", 403, :forbidden, []},
      {stranger, "#{nested.(unknown)}/#{own.id}", 403, :forbidden, []},
      {stranger, nested.(unknown), 403, :forbidden, []},
      {stranger, "#{top}?project_id=#{unknown}", 403, :forbidden, []},
      {stranger, "#{nested.("not-a-uuid")}/#{own.id}", 403, :forbidden, []},
      {stranger, nested.("not-a-uuid"), 403, :forbidden, []},
      {short_of_mfa, "#{top}/#{guarded_one.id}", 403, :forbidden, []},
      {short_of_mfa, "#{top}/#{unknown}", 403, :forbidden, []},
      {short_of_mfa, "#{top}/not-a-uuid", 403, :forbidden, []},
      {short_of_mfa, "#{nested.(guarded.id)}/#{guarded_one.id}", 403, :forbidden,
       []},
      {short_of_mfa, "#{nested.(guarded.id)}/#{unknown}", 403, :forbidden, []},
      {short_of_mfa, "#{nested.(guarded.id)}/not-a-uuid", 403, :forbidden, []},
      {short_of_mfa, nested.(guarded.id), 403, :forbidden, []},
      {short_of_mfa, "#{top}?project_id=#{guarded.id}", 403, :forbidden, []},
      {member, "#{top}/#{unknown}", 403, :forbidden, []},
      {member, "#{top}/not-a-uuid", 403, :forbidden, []},
      {member, "#{top}/#{unknown}?project_id=#{project.id}", 403, :forbidden,
       []},
      {member, "#{nested.(project.id)}/#{unknown}", 404, :not_found, []},
      {member, "#{nested.(project.id)}/#{elsewhere.id}", 404, :not_found, []},
      {member, "#{nested.(project.id)}/not-a-uuid", 400, :invalid_parameter,
       path_id},
      {member, "#{nested.(unknown)}/#{own.id}", 403, :forbidden, []},
      {member, nested.(unknown), 403, :forbidden, []},
      {member, "#{top}?project_id=#{unknown}", 403, :forbidden, []},
      {member, nested.("not-a-uuid"), 403, :forbidden, []},
      {superuser, "#{top}/#{own.id}", 403, :forbidden, []},
      {superuser, "#{top}/#{unknown}", 403, :forbidden, []},
      {superuser, "#{top}/not-a-uuid", 403, :forbidden, []},
      {superuser, "#{nested.(project.id)}/#{own.id}", 403, :forbidden, []},
      {superuser, "#{nested.(project.id)}/#{unknown}", 403, :forbidden, []},
      {superuser, "#{nested.(project.id)}/not-a-uuid", 403, :forbidden, []},
      {superuser, nested.(project.id), 403, :forbidden, []},
      {superuser, "#{top}?project_id=#{project.id}", 403, :forbidden, []},
      {superuser, "#{nested.(unknown)}/#{own.id}", 404, :not_found, []},
      {superuser, nested.(unknown), 404, :not_found, []},
      {superuser, "#{top}?project_id=#{unknown}", 404, :not_found, []},
      {superuser, "#{nested.("not-a-uuid")}/#{own.id}", 400, :invalid_parameter,
       path_project_id},
      {superuser, nested.("not-a-uuid"), 400, :invalid_parameter,
       path_project_id},
      {superuser, "#{top}?project_id=not-a-uuid", 400, :invalid_parameter,
       query_project_id},
      {superuser, "#{top}?project_id[]=x", 400, :invalid_parameter,
       query_project_id},
      {service_account, "#{top}/#{unknown}", 404, :not_found, []},
      {service_account, "#{top}/not-a-uuid", 400, :invalid_parameter, path_id},
      {service_account, "#{nested.(unknown)}/#{own.id}", 404, :not_found, []},
      {service_account, nested.(unknown), 404, :not_found, []},
      {service_account, "#{top}?project_id=#{unknown}", 404, :not_found, []},
      {service_account, nested.("not-a-uuid"), 400, :invalid_parameter,
       path_project_id},
      {service_account, "#{top}?project_id=not-a-uuid", 400, :invalid_parameter,
       query_project_id},
      {service_account, "#{top}?project_id[]=x", 400, :invalid_parameter,
       query_project_id}
    ]
  end
end
