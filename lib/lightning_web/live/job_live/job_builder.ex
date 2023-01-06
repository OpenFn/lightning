defmodule LightningWeb.JobLive.JobBuilder do
  @moduledoc """
  Job Builder Panel
  """

  use LightningWeb, :live_component
  alias LightningWeb.Components.Form
  alias Lightning.Jobs
  alias Lightning.Jobs.Job

  import LightningWeb.JobLive.JobBuilderComponents

  defp id(id) do
    "builder-#{id}"
  end

  def send_adaptor(job_id, adaptor) do
    send_update(__MODULE__,
      id: id(job_id),
      job_adaptor: adaptor,
      event: :job_adaptor_changed
    )
  end

  def send_credential(job_id, credential) do
    send_update(__MODULE__,
      id: id(job_id),
      credential: credential,
      event: :credential_changed
    )
  end

  def update_cron_expression(job_id, cron_expression) do
    send_update(__MODULE__,
      id: id(job_id),
      cron_expression: cron_expression,
      event: :cron_expression_changed
    )
  end

  def follow_run(job_id, attempt_run) do
    send_update(__MODULE__,
      id: id(job_id),
      attempt_run: attempt_run,
      event: :follow_run
    )
  end

  attr :return_to, :string, required: true
  attr :params, :map, default: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      x-data="{ tab: window.location.hash.substring(1) || 'setup' }"
      class="h-full bg-white shadow-xl ring-1 ring-black ring-opacity-5"
      x-show="tab"
    >
      <div class="flex flex-col h-full">
        <div class="flex-none">
          <.tab_bar id={@id} default_hash="setup">
            <!-- The tabs navigation -->
            <.tab_item hash="setup">Setup</.tab_item>
            <.tab_item hash="input">Input</.tab_item>
            <.tab_item hash="editor">
              Editor
              <.when_invalid changeset={@changeset} field={:body}>
                <Heroicons.exclamation_circle mini class="ml-1 w-4 h-4 text-red-500" />
              </.when_invalid>
            </.tab_item>
            <.tab_item hash="output">Output</.tab_item>
          </.tab_bar>
        </div>
        <div class="grow overflow-y-auto p-3">
          <!-- The tabs content -->
          <.panel_content for_hash="setup">
            <.form
              :let={f}
              for={@changeset}
              as={:job_form}
              id="job-form"
              phx-target={@myself}
              phx-change="validate"
              phx-submit="save"
              class="h-full"
            >
              <div class="md:grid md:grid-cols-4 md:gap-4 @container">
                <div class="md:col-span-2">
                  <Form.text_field form={f} label="Job Name" id={:name} />
                </div>
                <div class="md:col-span-2">
                  <Form.check_box form={f} id={:enabled} />
                </div>
                <div class="md:col-span-4">
                  <%= for t <- inputs_for(f, :trigger) do %>
                    <.trigger_picker
                      form={t}
                      upstream_jobs={@upstream_jobs}
                      on_cron_change={
                        fn cron_expression ->
                          update_cron_expression(@job_id, cron_expression)
                        end
                      }
                    />
                  <% end %>
                </div>
                <div class="col-span-4">
                  <.live_component
                    id="adaptor-picker"
                    module={LightningWeb.JobLive.AdaptorPicker}
                    on_change={fn adaptor -> send_adaptor(@job_id, adaptor) end}
                    form={f}
                  />
                </div>
                <div class="md:col-span-2">
                  <Components.Jobs.credential_select
                    form={f}
                    credentials={@credentials}
                  />
                  <button
                    id="new-credential-launcher"
                    type="button"
                    class="text-indigo-400 underline underline-offset-2 hover:text-indigo-500 text-xs"
                    phx-click="open_new_credential"
                    phx-target={@myself}
                  >
                    New credential
                  </button>
                </div>
              </div>
            </.form>
          </.panel_content>
          <.panel_content for_hash="input">
            <%= if @is_persisted do %>
              <.live_component
                module={LightningWeb.JobLive.ManualRunComponent}
                current_user={@current_user}
                id={"manual-job-#{@job_id}"}
                job_id={@job_id}
                job={@job}
                on_run={fn attempt_run -> follow_run(@job_id, attempt_run) end}
                project={@project}
                builder_state={@builder_state}
              />
            <% else %>
              <p>Please save your Job first.</p>
            <% end %>
          </.panel_content>
          <.panel_content for_hash="editor">
            <div class="flex flex-col h-full">
              <div
                phx-hook="Editor"
                phx-update="ignore"
                id={"job-editor-#{@job_id}"}
                class=" rounded-md border border-secondary-300 shadow-sm bg-vs-dark h-96"
                data-adaptor={@resolved_job_adaptor}
                data-source={@job_body}
                data-change-event="job_body_changed"
                phx-target={@myself}
              />
              <div class="flex-1 overflow-auto">
                <.docs_component adaptor={@resolved_job_adaptor} />
              </div>
            </div>
          </.panel_content>
          <.panel_content for_hash="output">
            <%= if @follow_run_id do %>
              <div class="h-full">
                <%= live_render(
                  @socket,
                  LightningWeb.RunLive.RunViewerLive,
                  id: "run-viewer-#{@follow_run_id}",
                  session: %{"run_id" => @follow_run_id},
                  sticky: true
                ) %>
              </div>
            <% else %>
              <div class="w-1/2 h-16 text-center m-auto pt-4">
                <div class="font-semibold text-gray-500 pb-2">
                  No Run
                </div>
                <div class="text-xs text-gray-400">
                  Select a dataclip on the
                  <a
                    href="#input"
                    class="text-indigo-400 underline underline-offset-2 hover:text-indigo-500"
                  >
                    Input
                  </a>
                  tab,
                  and click the Run button to start one.
                </div>
              </div>
            <% end %>
          </.panel_content>
        </div>
        <div class="flex-none sticky p-3 border-t">
          <!-- BUTTONS -->
          <%= live_patch("Cancel",
            class:
              "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500",
            to: @return_to
          ) %>
          <Form.submit_button
            disabled={!@changeset.valid?}
            phx-disable-with="Saving"
            form="job-form"
          >
            Save
          </Form.submit_button>
          <%= if @job_id != "new" do %>
            <Common.button
              id="delete-job"
              text="Delete"
              phx-click="delete"
              phx-target={@myself}
              phx-value-id={@job_id}
              disabled={!@is_deletable}
              data={[
                confirm:
                  "This action is irreversible, are you sure you want to continue?"
              ]}
              title={
                if @is_deletable,
                  do: "Delete this job",
                  else:
                    "Impossible to delete upstream jobs. Please delete all associated downstream jobs first."
              }
              color="red"
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    job = Jobs.get_job!(id)

    case Jobs.delete_job(job) do
      {:ok, _} ->
        LightningWeb.Endpoint.broadcast!(
          "project_space:#{socket.assigns.project.id}",
          "update",
          %{workflow_id: job.workflow_id}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Job deleted successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Unable to delete this job because it has downstream jobs"
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"job_form" => params}, socket) do
    {:noreply, socket |> assign_changeset_and_params(params)}
  end

  def handle_event("job_body_changed", %{"source" => source}, socket) do
    {:noreply, socket |> assign_changeset_and_params(%{"body" => source})}
  end

  def handle_event("open_new_credential", _params, socket) do
    LightningWeb.ModalPortal.show_modal(
      LightningWeb.CredentialLive.CredentialEditModal,
      %{
        action: :new,
        confirm: {"Save", type: "submit", form: "song-form"},
        credential: %Lightning.Credentials.Credential{
          user_id: socket.assigns.current_user.id
        },
        current_user: socket.assigns.current_user,
        id: :new,
        on_save: fn credential ->
          send_credential(socket.assigns.job_id, credential)
          LightningWeb.ModalPortal.close_modal()
        end,
        project: socket.assigns.project,
        projects: [],
        show_project_credentials: false,
        title: "Create Credential"
      }
    )

    {:noreply, socket}
  end

  def handle_event("save", %{"job_form" => params}, socket) do
    params = merge_params(socket.assigns.params, params)

    %{job: job, workflow: workflow, is_persisted: is_persisted} = socket.assigns

    changeset =
      build_changeset(job, params, workflow)
      |> Map.put(:action, if(is_persisted, do: :update, else: :insert))

    socket =
      changeset
      |> Lightning.Repo.insert_or_update()
      |> case do
        {:ok, _job} ->
          on_save_success(socket)

        {:error, %Ecto.Changeset{} = changeset} ->
          assign(socket, changeset: changeset, params: params)
      end

    {:noreply, socket}
  end

  defp on_save_success(socket) do
    workflow_id =
      socket.assigns.changeset |> Ecto.Changeset.get_field(:workflow_id)

    LightningWeb.Endpoint.broadcast!(
      "project_space:#{socket.assigns.project.id}",
      "update",
      %{workflow_id: workflow_id}
    )

    socket
    |> put_flash(:info, "Job updated successfully")
    |> push_patch(to: socket.assigns.return_to)
  end

  defp merge_params(prev, next) do
    Map.merge(prev, next, fn k, v1, v2 ->
      case k do
        "trigger" ->
          Map.merge(v1, v2)

        _ ->
          v2
      end
    end)
  end

  defp assign_changeset_and_params(socket, params) do
    socket
    |> update(:params, fn prev -> merge_params(prev, params) end)
    |> update(:changeset, fn _changeset, %{params: params, job: job} ->
      build_changeset(job, params, socket.assigns.workflow)
      |> Map.put(:action, :validate)
    end)
  end

  defp build_changeset(job, params, nil) do
    Job.changeset(job, params)
  end

  defp build_changeset(job, params, workflow) do
    Ecto.Changeset.change(job)
    |> Job.put_workflow(workflow)
    |> Job.changeset(params)
  end

  defp is_deletable(%Job{id: nil}), do: false

  defp is_deletable(%Job{id: job_id}),
    do:
      Lightning.Jobs.get_job!(job_id)
      |> Lightning.Jobs.get_downstream_jobs_for()
      |> Enum.count() == 0

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(follow_run_id: nil)}
  end

  @impl true
  def update(
        %{
          id: id,
          job: job,
          project: project,
          current_user: current_user,
          return_to: return_to,
          builder_state: builder_state
        } = assigns,
        socket
      ) do
    job = job |> Lightning.Repo.preload([:trigger, :workflow])
    credentials = Lightning.Projects.list_project_credentials(project)
    params = assigns[:params] || %{}

    changeset = build_changeset(job, params, assigns[:workflow])

    upstream_jobs =
      Lightning.Jobs.get_upstream_jobs_for(
        changeset
        |> Ecto.Changeset.apply_changes()
      )

    is_deletable = is_deletable(job)

    {:ok,
     socket
     |> assign(
       id: id,
       job: job,
       project: project,
       current_user: current_user,
       job_body: job.body,
       job_adaptor: job.adaptor,
       resolved_job_adaptor:
         Lightning.AdaptorRegistry.resolve_adaptor(job.adaptor),
       return_to: return_to,
       workflow: assigns[:workflow],
       changeset: changeset,
       credentials: credentials,
       builder_state: builder_state,
       upstream_jobs: upstream_jobs,
       is_deletable: is_deletable
     )
     |> assign_new(:params, fn -> params end)
     |> assign_new(:job_id, fn -> job.id || "new" end)
     |> assign_new(:is_persisted, fn -> not is_nil(job.id) end)}
  end

  def update(%{event: :job_adaptor_changed, job_adaptor: job_adaptor}, socket) do
    {:ok,
     socket
     |> assign(job_adaptor: job_adaptor)
     |> assign(
       resolved_job_adaptor:
         Lightning.AdaptorRegistry.resolve_adaptor(job_adaptor)
     )
     |> assign_changeset_and_params(%{"adaptor" => job_adaptor})}
  end

  def update(
        %{event: :cron_expression_changed, cron_expression: cron_expression},
        socket
      ) do
    %{id: trigger_id} =
      socket.assigns.changeset
      |> Ecto.Changeset.get_field(:trigger)

    {:ok,
     socket
     |> assign_changeset_and_params(%{
       "trigger" => %{"cron_expression" => cron_expression, "id" => trigger_id}
     })}
  end

  def update(%{event: :credential_changed, credential: credential}, socket) do
    %{id: project_credential_id} = credential.project_credentials |> List.first()

    {:ok,
     socket
     |> assign(
       credentials:
         Lightning.Projects.list_project_credentials(socket.assigns.project)
     )
     |> assign_changeset_and_params(%{
       "project_credential_id" => project_credential_id
     })}
  end

  def update(%{event: :follow_run, attempt_run: attempt_run}, socket) do
    {:ok, socket |> assign(follow_run_id: attempt_run.run.id)}
  end
end
