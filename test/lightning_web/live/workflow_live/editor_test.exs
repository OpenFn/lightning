defmodule LightningWeb.WorkflowLive.EditorTest do
  use LightningWeb.ConnCase, async: true
  use Oban.Testing, repo: Lightning.Repo

  import Phoenix.LiveViewTest
  import Lightning.WorkflowLive.Helpers
  import Lightning.Factories

  import Ecto.Query

  alias Lightning.Invocation

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :create_workflow

  test "can edit a jobs body", %{
    project: project,
    workflow: workflow,
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

    job = workflow.jobs |> List.first()

    view |> select_node(job)

    view |> job_panel_element(job)

    assert view |> job_panel_element(job) |> render() =~ "First Job",
           "can see the job name in the panel"

    view |> click_edit(job)

    assert view |> job_edit_view(job) |> has_element?(),
           "can see the job_edit_view component"
  end

  test "mounts the JobEditor with the correct attrs", %{
    conn: conn,
    project: project,
    workflow: workflow
  } do
    job = workflow.jobs |> hd()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
      )

    actual_attrs =
      view
      |> element("div[phx-hook='JobEditor']")
      |> render()
      |> Floki.parse_fragment!()
      |> Enum.at(0)
      |> then(fn {_, attrs, _} ->
        Map.new(attrs)
      end)

    # The JobEditor component should be mounted with a resolved version number
    assert job.adaptor == "@openfn/language-common@latest"
    assert {"data-adaptor", "@openfn/language-common@1.6.2"} in actual_attrs

    assert {"data-change-event", "job_body_changed"} in actual_attrs
    assert {"data-disabled", "false"} in actual_attrs
    assert {"data-source", job.body} in actual_attrs
    assert {"id", "job-editor-#{job.id}"} in actual_attrs
    assert {"phx-hook", "JobEditor"} in actual_attrs
    assert {"phx-target", "1"} in actual_attrs
    assert {"phx-update", "ignore"} in actual_attrs
  end

  describe "manual runs" do
    @tag role: :viewer
    test "viewers can't run a job", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      job = workflow.jobs |> hd()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
        )

      # dataclip dropdown is disabled
      assert view
             |> element(
               ~s{#manual-job-#{job.id} form select[name='manual[dataclip_id]'][disabled]}
             )
             |> has_element?()

      assert view
             |> element(
               ~s{button[type='submit'][form='manual_run_form'][disabled]}
             )
             |> has_element?()

      assert view |> render_click("manual_run_submit", %{"manual" => %{}}) =~
               "You are not authorized to perform this action."
    end

    test "can see the last 3 dataclips", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      job = workflow.jobs |> hd()

      dataclip_ids =
        insert_list(4, :run,
          job: job,
          inserted_at: fn ->
            ExMachina.sequence(:past_timestamp, fn i ->
              DateTime.utc_now() |> DateTime.add(-i)
            end)
          end
        )
        |> Enum.map(fn run ->
          run.input_dataclip_id
        end)
        |> Enum.reverse()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
        )

      assert view
             |> element(
               ~s{#manual-job-#{job.id} form select[name='manual[dataclip_id]'] option},
               "Create a new dataclip"
             )
             |> has_element?()

      for dataclip_id <- dataclip_ids |> Enum.slice(0..2) do
        assert view
               |> element(
                 ~s{#manual-job-#{job.id} form select[name='manual[dataclip_id]'] option},
                 dataclip_id
               )
               |> has_element?()
      end
    end

    test "can create a new dataclip", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      assert Invocation.list_dataclips_for_job(job) |> Enum.count() == 0

      body = %{"a" => 1}

      view
      |> form("#manual-job-#{job.id} form",
        manual: %{
          body: Jason.encode!(body)
        }
      )
      |> render_submit()

      assert where(
               Lightning.Invocation.Dataclip,
               [d],
               d.body == ^body and d.type == :saved_input and
                 d.project_id == ^p.id
             )
             |> Lightning.Repo.exists?()
    end

    @tag role: :editor
    test "can't with a new dataclip if it's invalid", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      view
      |> form("#manual-job-#{job.id} form", %{
        "manual" => %{"body" => "["}
      })
      |> render_change()

      view
      |> element("#manual-job-#{job.id} form")
      |> render_submit()

      refute_enqueued(worker: Lightning.Pipeline)

      assert view
             |> element("#manual-job-#{job.id} form")
             |> render()

      assert view |> has_element?("#manual-job-#{job.id} form", "Invalid JSON")
    end

    test "can run a job", %{conn: conn, project: p, workflow: w} do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      assert view
             |> element(
               "button[type='submit'][form='manual_run_form'][disabled]"
             )
             |> has_element?()

      view
      |> form("#manual-job-#{job.id} form", %{
        "manual" => %{"body" => "{}"}
      })
      |> render_change()

      refute view
             |> element(
               "button[type='submit'][form='manual_run_form'][disabled]"
             )
             |> has_element?()

      assert [] == live_children(view)

      view
      |> element("#manual-job-#{job.id} form")
      |> render_submit()

      assert [run_viewer] = live_children(view)

      render_async(run_viewer)

      assert run_viewer
             |> element("li:nth-child(4) dd", "Pending")
             |> has_element?()
    end

    test "the new dataclip is selected after running job", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      existing_dataclip = insert(:dataclip, project: p)

      insert(:workorder,
        workflow: w,
        dataclip: existing_dataclip,
        attempts: [
          build(:attempt,
            dataclip: existing_dataclip,
            starting_job: job,
            runs: [build(:run, job: job, input_dataclip: existing_dataclip)]
          )
        ]
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      body = %{"val" => Ecto.UUID.generate()}

      dataclip_query =
        where(
          Lightning.Invocation.Dataclip,
          [d],
          d.type == :saved_input and
            d.project_id == ^p.id
        )

      refute Lightning.Repo.exists?(dataclip_query)
      refute render(view) =~ body["val"]

      view
      |> form("#manual-job-#{job.id} form", %{
        manual: %{body: Jason.encode!(body)}
      })
      |> render_submit()

      assert render(view) =~ body["val"]

      new_dataclip = Lightning.Repo.one(dataclip_query)

      element =
        view
        |> element(
          "select#manual_run_form_dataclip_id  option[value='#{new_dataclip.id}']"
        )

      assert render(element) =~ "selected"

      refute view
             |> element(
               ~s{button[type='submit'][form='manual_run_form'][disabled]}
             )
             |> has_element?()
    end
  end

  describe "Editor events" do
    test "can handle request_metadata event", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      project_credential = insert(:project_credential, project: project)
      job = workflow.jobs |> hd()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
        )

      assert has_element?(view, "#job-editor-pane-#{job.id}")

      assert view
             |> with_target("#job-editor-pane-#{job.id}")
             |> render_click("request_metadata", %{})

      assert_push_event(view, "metadata_ready", %{"error" => "no_credential"})

      view
      |> form("#workflow-form",
        workflow: %{
          jobs: %{
            "0" => %{
              "project_credential_id" => project_credential.id
            }
          }
        }
      )
      |> render_change()

      assert view
             |> with_target("#job-editor-pane-#{job.id}")
             |> render_click("request_metadata", %{})

      assert_push_event(view, "metadata_ready", %{
        "error" => "no_metadata_function"
      })
    end
  end
end
