defmodule LightningWeb.JobLive.JobBuilder do
  @moduledoc """
  Job Builder Panel
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form
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
  attr :can_edit_job, :boolean, required: true
  attr :can_run_job, :boolean, required: true

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
          <LightningWeb.Components.Common.tab_bar
            id={@id}
            orientation="horizontal"
            default_hash="setup"
          >
            <!-- The tabs navigation -->
            <LightningWeb.Components.Common.tab_item
              orientation="horizontal"
              hash="setup"
            >
              Setup
            </LightningWeb.Components.Common.tab_item>
            <LightningWeb.Components.Common.tab_item
              orientation="horizontal"
              hash="input"
            >
              Input
            </LightningWeb.Components.Common.tab_item>
            <LightningWeb.Components.Common.tab_item
              orientation="horizontal"
              hash="editor"
            >
              Editor
              <.when_invalid changeset={@changeset} field={:body}>
                <Heroicons.exclamation_circle mini class="ml-1 w-4 h-4 text-red-500" />
              </.when_invalid>
            </LightningWeb.Components.Common.tab_item>
            <LightningWeb.Components.Common.tab_item
              orientation="horizontal"
              hash="output"
            >
              Output
            </LightningWeb.Components.Common.tab_item>
          </LightningWeb.Components.Common.tab_bar>
        </div>
        <div class="grow overflow-y-auto p-3">
          <!-- The tabs content -->
          <LightningWeb.Components.Common.panel_content for_hash="setup">
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
              <div class="md:grid md:grid-cols-6 md:gap-4 @container">
                <div class="col-span-6">
                  <Form.check_box
                    form={f}
                    field={:enabled}
                    disabled={!@can_edit_job}
                  />
                </div>
                <div class="col-span-6 @md:col-span-4">
                  <Form.text_field
                    form={f}
                    label="Job Name"
                    field={:name}
                    disabled={!@can_edit_job}
                  />
                </div>
                <div class="col-span-6">
                  <%= for t <- inputs_for(f, :trigger) do %>
                    <.trigger_picker
                      form={t}
                      upstream_jobs={@upstream_jobs}
                      on_cron_change={
                        fn params ->
                          cron_expression =
                            get_in(params, ["job_form", "trigger", "cron_expression"])

                          update_cron_expression(@job_id, cron_expression)
                        end
                      }
                      disabled={!@can_edit_job}
                    />
                  <% end %>
                </div>
                <div class="col-span-6">
                  <.live_component
                    id="adaptor-picker"
                    module={LightningWeb.JobLive.AdaptorPicker}
                    on_change={
                      fn params ->
                        adaptor = get_in(params, ["job_form", "adaptor"])
                        send_adaptor(@job_id, adaptor)
                      end
                    }
                    form={f}
                    disabled={!@can_edit_job}
                  />
                </div>
                <div class="col-span-6 @md:col-span-4">
                  <Components.Jobs.credential_select
                    form={f}
                    credentials={@credentials}
                    disabled={!@can_edit_job}
                    myself={@myself}
                  />
                </div>
              </div>
            </.form>
          </LightningWeb.Components.Common.panel_content>
          <LightningWeb.Components.Common.panel_content for_hash="input">
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
                can_run_job={@can_run_job}
                return_to={@return_to}
              />
            <% else %>
              <p>Please save your Job first.</p>
            <% end %>
          </LightningWeb.Components.Common.panel_content>
          <LightningWeb.Components.Common.panel_content for_hash="editor">
            <.job_editor_component
              adaptor={@resolved_job_adaptor}
              source={@job_body}
              id={"job-editor-#{@job_id}"}
              disabled={!@can_edit_job}
              phx-target={@myself}
            />
          </LightningWeb.Components.Common.panel_content>
          <LightningWeb.Components.Common.panel_content for_hash="output">
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
          </LightningWeb.Components.Common.panel_content>
        </div>
        <div class="flex-none sticky p-3 border-t">
          <%= live_patch("Close",
            class:
              "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500",
            to: @return_to
          ) %>
          <Form.submit_button
            disabled={!(@changeset.valid? and @can_edit_job)}
            phx-disable-with="Saving"
            form="job-form"
          >
            <%= if @job_id != "new", do: "Save", else: "Create" %>
          </Form.submit_button>
          <%= if @job_id != "new" do %>
            <Common.button
              id="delete_job"
              text="Delete"
              phx-click="delete_job"
              phx-value-id={@job_id}
              disabled={!(@is_deletable and @can_edit_job)}
              data-confirm="This action is irreversible, are you sure you want to continue?"
              title={delete_title(@is_deletable, @can_edit_job)}
              color="red"
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def delete_title(is_deletable, can_delete_job) do
    case {is_deletable, can_delete_job} do
      {true, true} ->
        "Delete this job"

      {false, true} ->
        "Impossible to delete upstream jobs. Please delete all associated downstream jobs first."

      {_, false} ->
        "You are not authorized to perform this action."
    end
  end

  @impl true
  def handle_event("validate", %{"job_form" => params}, socket) do
    {:noreply, socket |> assign_changeset_and_params(params)}
  end

  def handle_event("job_body_changed", %{"source" => source}, socket) do
    {:noreply, socket |> assign_changeset_and_params(%{"body" => source})}
  end

  def handle_event("request_metadata", _params, socket) do
    pid = self()

    adaptor = socket.assigns.changeset |> Ecto.Changeset.get_field(:adaptor)

    credential =
      socket.assigns.changeset |> Ecto.Changeset.get_field(:credential)

    Task.start(fn ->
      metadata =
        Lightning.MetadataService.fetch(adaptor, credential)
        |> case do
          {:error, %{type: error_type}} ->
            %{"error" => error_type}

          {:ok, metadata} ->
            metadata
        end

      send_update(pid, __MODULE__,
        id: id(socket.assigns.job_id),
        metadata: metadata,
        event: :metadata_ready
      )
    end)

    {:noreply, socket}
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
    if socket.assigns.can_edit_job do
      params = merge_params(socket.assigns.params, params)

      %{job: job, workflow: workflow, is_persisted: is_persisted} =
        socket.assigns

      changeset =
        build_changeset(job, params, workflow)
        |> Map.put(:action, if(is_persisted, do: :update, else: :insert))

      socket =
        changeset
        |> Lightning.Repo.insert_or_update()
        |> case do
          {:ok, job} ->
            on_save_success(socket, job)

          {:error, %Ecto.Changeset{} = changeset} ->
            assign(socket, changeset: changeset, params: params)
        end

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")
       |> push_patch(to: socket.assigns.return_to)}
    end
  end

  defp on_save_success(socket, job) do
    workflow_id =
      socket.assigns.changeset |> Ecto.Changeset.get_field(:workflow_id)

    LightningWeb.Endpoint.broadcast!(
      "project_space:#{socket.assigns.project.id}",
      "update",
      %{workflow_id: workflow_id}
    )

    message =
      if socket.assigns.job.id != job.id,
        do: "Job created successfully",
        else: "Job updated successfully"

    socket
    |> put_flash(:info, message)
    |> push_patch(to: socket.assigns.return_to <> "/j/#{job.id}")
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
          can_edit_job: can_edit_job,
          can_run_job: can_run_job,
          can_delete_job: can_delete_job,
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
       is_deletable: is_deletable(job),
       can_edit_job: can_edit_job,
       can_run_job: can_run_job,
       can_delete_job: can_delete_job
     )
     |> assign_new(:params, fn -> params end)
     |> assign_new(:job_id, fn -> job.id || "new" end)
     |> assign_new(:is_persisted, fn -> not is_nil(job.id) end)}
  end

  def update(%{event: :metadata_ready, metadata: metadata}, socket) do
    {:ok, socket |> push_event("metadata_ready", metadata)}
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
