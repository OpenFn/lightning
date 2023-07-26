defmodule LightningWeb.JobLive.ManualRunComponent do
  use LightningWeb, :live_component

  defmodule ManualWorkorder do
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      embeds_one :project, Lightning.Projects.Project
      embeds_one :user, Lightning.Accounts.User
      embeds_one :job, Lightning.Jobs.Job
      field :dataclip_id, Ecto.UUID
      field :body, :string
    end

    def changeset(%{project: project, job: job, user: user}, attrs) do
      %__MODULE__{}
      |> cast(attrs, [:body, :dataclip_id])
      |> put_embed(:project, project)
      |> put_embed(:job, job)
      |> put_embed(:user, user)
      |> validate_required([:project, :job, :user])
      |> Lightning.Validators.validate_exclusive(
        [:dataclip_id, :body],
        "Dataclip and custom body are mutually exclusive."
      )
      |> Lightning.Validators.validate_one_required(
        [:dataclip_id, :body],
        "Either a dataclip or a custom body must be present."
      )
    end
  end

  alias LightningWeb.Components.Form

  attr :job, :map, required: true
  attr :on_run, :any, required: true
  attr :user, :map, required: true
  attr :selected_dataclip_id, :string, required: true

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        run_button_disabled: !(assigns.changeset.valid? and assigns.can_run_job)
      )

    ~H"""
    <div id={@id} class="h-full">
      <.form
        :let={f}
        for={@changeset}
        as={:manual_workorder}
        class="h-full flex flex-col gap-4"
        phx-target={@myself}
        phx-change="change"
        phx-submit="run"
      >
        <.dataclip_selector form={f} phx-target={@myself} dataclips={@dataclips} />
        <div :if={is_nil(@selected_dataclip)} class="flex-1 flex flex-col">
          <Form.text_area form={f} field={:body} phx-debounce="300" />
        </div>
        <div :if={@selected_dataclip} class="flex-1 flex flex-col gap-4">
          <div>
            <div class="flex flex-row">
              <div class="basis-1/2 font-semibold text-secondary-700">
                Dataclip Type
              </div>
              <div class="basis-1/2 text-right">
                <Common.dataclip_type_pill dataclip={@selected_dataclip} />
              </div>
            </div>
          </div>
          <div class="h-32 overflow-y-auto">
            <LightningWeb.RunLive.Components.log_view log={
              format_dataclip_body(@selected_dataclip)
            } />
          </div>
          <div class="flex-none">
            <div class="font-semibold text-secondary-700">State Assembly</div>
            <div class="text-right text-sm">
              <%= if(@selected_dataclip.type == :http_request) do %>
                The JSON shown here is the <em>body</em>
                of an HTTP request. The state assembler will place this payload into
                <code>state.data</code>
                when the job is run, before adding <code>state.configuration</code>
                from your selected credential.
              <% else %>
                The state assembler will overwrite the <code>configuration</code>
                attribute below with the body of the currently selected credential.
              <% end %>
            </div>
          </div>
        </div>
        <div class="flex-none flex place-content-end">
          <Form.submit_button
            phx-disable-with="Enqueuing..."
            disabled={!@changeset.valid?}
          >
            Run
          </Form.submit_button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(changeset: nil)}
  end

  @impl true
  def update(
        %{
          id: id,
          job: job,
          dataclips: dataclips,
          on_run: on_run,
          can_run_job: can_run_job,
          project: project,
          user: user
        },
        socket
      ) do
    {:ok,
     socket
     |> assign(
       can_run_job: can_run_job,
       dataclips: dataclips,
       id: id,
       job: job,
       project: project,
       user: user,
       on_run: on_run
     )
     |> update(:changeset, fn
       nil, %{job: job, user: user, project: project} ->
         dataclip_id = dataclips |> List.first(%{id: nil}) |> Map.get(:id)

         ManualWorkorder.changeset(%{project: project, job: job, user: user}, %{
           dataclip_id: dataclip_id
         })

       current, _ ->
         current
     end)
     |> set_selected_dataclip()}
  end

  @impl true
  def handle_event("run", %{"manual_workorder" => params}, socket) do
    case socket.assigns.can_run_job do
      true ->
        ManualWorkorder.changeset(socket.assigns, params)
        |> create_manual_workorder()
        |> case do
          {:ok, %{attempt_run: attempt_run}} ->
            socket.assigns.on_run.(attempt_run)

            {:noreply, socket}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(changeset: changeset |> Map.put(:action, :validate))}
        end

      false ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to perform this action.")
         |> push_patch(to: socket.assigns.return_to)}
    end
  end

  def handle_event("change", %{"manual_workorder" => params}, socket) do
    changeset =
      ManualWorkorder.changeset(socket.assigns, params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset) |> set_selected_dataclip()}
  end

  attr :dataclips, :list, required: true
  attr :form, :map, required: true
  attr :rest, :global

  defp dataclip_selector(assigns) do
    assigns =
      assigns
      |> assign(
        options: assigns.dataclips |> Enum.map(&{&1.id, &1.id}),
        rest: assigns |> Map.get(:rest, %{}) |> Map.take([:"phx-target"])
      )

    ~H"""
    <div class="flex">
      <div class="flex-grow">
        <Form.select_field
          form={@form}
          name={:dataclip_id}
          values={@options}
          prompt="Create a new dataclip"
          {@rest}
        />
      </div>
    </div>
    """
  end

  defp format_dataclip_body(dataclip) do
    dataclip.body
    |> Jason.encode!()
    |> Jason.Formatter.pretty_print()
    |> String.split("\n")
  end

  defp create_manual_workorder(changeset) do
    with {:ok, manual_workorder} <-
           Ecto.Changeset.apply_action(changeset, :validate),
         {:ok, dataclip} <- find_or_create_dataclip(manual_workorder) do
      %{user: user, job: job} = manual_workorder
      # HACK: Oban's testing functions only apply to `self` and LiveView
      # tests run in child processes, so for now we need to set the testing
      # mode from within the process.
      Process.put(:oban_testing, :manual)

      Lightning.WorkOrderService.create_manual_workorder(job, dataclip, user)
    else
      {:error, :not_found} ->
        {:error,
         changeset |> Ecto.Changeset.add_error(:dataclip_id, "not found")}

      {:error, %Ecto.Changeset{data: %Lightning.Invocation.Dataclip{}}} ->
        {:error, changeset |> Ecto.Changeset.add_error(:body, "Invalid body")}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp find_or_create_dataclip(manual_workorder) do
    manual_workorder
    |> case do
      %{dataclip_id: dataclip_id, body: nil} ->
        Lightning.Invocation.get_dataclip(dataclip_id)
        |> case do
          nil ->
            {:error, :not_found}

          d ->
            {:ok, d}
        end

      %{dataclip_id: nil, body: body, project: project} ->
        body =
          body
          |> Jason.decode()
          |> case do
            {:ok, body} ->
              body

            {:error, _} ->
              body
          end

        Lightning.Invocation.create_dataclip(%{
          project_id: project.id,
          type: :run_result,
          body: body
        })
    end
  end

  defp set_selected_dataclip(socket) do
    %{changeset: changeset, dataclips: dataclips} = socket.assigns

    selected_dataclip =
      with dataclip_id when not is_nil(dataclip_id) <-
             Ecto.Changeset.get_field(changeset, :dataclip_id),
           dataclip when not is_nil(dataclip) <-
             Enum.find(dataclips, &match?(%{id: ^dataclip_id}, &1)) do
        dataclip
      end

    socket |> assign(selected_dataclip: selected_dataclip)
  end
end
