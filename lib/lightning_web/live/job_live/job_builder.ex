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
          <div class="flex gap-x-8 gap-y-2 border-b border-gray-200 dark:border-gray-600">
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
          </div>
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
                  <Form.text_field form={f} id={:name} />
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
                <div class="md:col-span-2">
                  <Components.Jobs.credential_select
                    form={f}
                    credentials={@credentials}
                  />
                  <button
                    id="new-credential-launcher"
                    type="button"
                    phx-click="open_new_credential"
                    phx-target={@myself}
                  >
                    New credential
                  </button>
                </div>
                <div class="col-span-4">
                  <.live_component
                    id="adaptor-picker"
                    module={LightningWeb.JobLive.AdaptorPicker}
                    on_change={fn adaptor -> send_adaptor(@job_id, adaptor) end}
                    form={f}
                  />
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
                project={@project}
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
                data-adaptor={@job_adaptor}
                data-source={@job_body}
                data-change-event="job_body_changed"
                phx-target={@myself}
              />
              <div class="flex-1 overflow-auto" style="max-width: 400px;">
                <.docs_component adaptor={@job_adaptor} />
              </div>
            </div>
          </.panel_content>
          <.panel_content for_hash="output">
            Output block
          </.panel_content>
        </div>
        <div class="flex-none sticky p-3 border-t">
          <!-- BUTTONS -->
          <%= live_patch("Cancel",
            class:
              "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500",
            to: Routes.project_workflow_path(@socket, :show, @project.id)
          ) %>
          <Form.submit_button
            disabled={!@changeset.valid?}
            phx-disable-with="Saving"
            form="job-form"
          >
            Save
          </Form.submit_button>
        </div>
      </div>
    </div>
    """
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
    LightningWeb.Endpoint.broadcast!(
      "project_space:#{socket.assigns.project.id}",
      "update",
      %{}
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

  # NOTE: consider multiple update functions to handle new, new from (job) and
  # inspecting attempt runs.
  @impl true
  def update(
        %{
          id: id,
          job: job,
          project: project,
          current_user: current_user,
          return_to: return_to
        } = assigns,
        socket
      ) do
    job = job |> Lightning.Repo.preload([:trigger, :workflow])
    credentials = Lightning.Projects.list_project_credentials(project)
    params = assigns[:params] || %{}

    changeset = build_changeset(job, params, assigns[:workflow])

    {:ok,
     socket
     |> assign(
       id: id,
       job: job,
       project: project,
       current_user: current_user,
       job_body: job.body,
       job_adaptor: job.adaptor,
       return_to: return_to,
       workflow: assigns[:workflow],
       changeset: changeset,
       credentials: credentials,
       upstream_jobs:
         Lightning.Jobs.get_upstream_jobs_for(
           changeset
           |> Ecto.Changeset.apply_changes()
         )
     )
     |> assign_new(:params, fn -> params end)
     |> assign_new(:job_id, fn -> job.id || "new" end)
     |> assign_new(:is_persisted, fn -> not is_nil(job.id) end)}
  end

  def update(%{event: :job_adaptor_changed, job_adaptor: job_adaptor}, socket) do
    {:ok,
     socket
     |> assign(job_adaptor: job_adaptor)
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
end
