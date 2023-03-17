defmodule LightningWeb.JobLive.ManualRunComponent do
  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  attr :job_id, :string, required: true
  attr :current_user, Lightning.Accounts.User, required: true
  attr :builder_state, :any, required: true
  attr :on_run, :any, required: true
  attr :selected_dataclip, Lightning.Invocation.Dataclip
  attr :project, Lightning.Projects.Project

  @impl true
  def render(%{changeset: changeset, can_run_job: can_run_job} = assigns) do
    assigns =
      assigns
      |> assign(run_button_disabled: !(changeset.valid? and can_run_job))

    ~H"""
    <div id={@id} class="h-full">
      <.form
        :let={f}
        for={@changeset}
        as={:manual_run}
        phx-target={@myself}
        phx-change="validate"
        class="h-full flex flex-col"
      >
        <%= error_tag(f, :dataclip_id) %>
        <Form.select_field
          form={f}
          name={:dataclip_id}
          id={:dataclip_id}
          values={@dataclips_options}
          selected={@selected_dataclip.id}
          phx-target={@myself}
          phx-change="validate"
        />
        <br />
        <div class="flex flex-col gap-2">
          <div class="flex gap-4 flex-row text-sm" id="dataclip-type">
            <div class="basis-1/2 font-semibold text-secondary-700">
              Dataclip Type
            </div>
            <div class="basis-1/2 text-right">
              <Common.dataclip_type_pill dataclip={@selected_dataclip} />
            </div>
          </div>
          <div class="flex gap-4 flex-row text-sm" id="dataclip-type">
            <div class="basis-1/2 font-semibold text-secondary-700">
              Initial State Assembly
            </div>
            <div class="basis-1/2 text-right">
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
        <%= if(@custom_input?) do %>
          <%= textarea(f, :body,
            class:
              "rounded-md mt-4 w-full font-mono bg-secondary-800 text-secondary-50 h-96"
          ) %>
          <%= error_tag(f, :body,
            class:
              "mt-1 focus:ring-primary-500 focus:border-primary-500 block w-full shadow-sm sm:text-sm border-secondary-300 rounded-md"
          ) %>
        <% else %>
          <LightningWeb.RunLive.Components.log_view log={@selected_dataclip.body} />
        <% end %>
        <div class="mt-2">
          <Common.button
            id="run-job"
            text="Run"
            disabled={@run_button_disabled}
            phx-click="confirm"
            phx-target={@myself}
          />
        </div>
      </.form>
    </div>
    """
  end

  defp get_current_dataclip(state, job_id) do
    if is_map_key(state, :dataclip) && is_map_key(state, :job_id) &&
         state.job_id == job_id do
      state.dataclip
    else
      nil
    end
  end

  @impl true
  def update(
        %{
          builder_state: builder_state,
          current_user: current_user,
          id: id,
          job_id: job_id,
          job: job,
          project: project,
          on_run: on_run,
          can_run_job: can_run_job,
          return_to: return_to
        },
        socket
      ) do
    dataclips =
      Lightning.Invocation.list_dataclips_for_job(%Lightning.Jobs.Job{
        id: job_id
      })

    dataclips_options =
      dataclips
      |> Enum.map(&{&1.id, &1.id})

    dataclips_options =
      if job.trigger.type in [:webhook, :cron] do
        dataclips_options ++ [{"New custom input", "custom"}]
      else
        dataclips_options
      end

    last_dataclip = List.first(dataclips)
    no_dataclip? = is_nil(last_dataclip)

    current_dataclip = get_current_dataclip(builder_state, job_id)

    has_current_dataclip? = not is_nil(current_dataclip)

    selected_dataclip =
      cond do
        no_dataclip? -> nil
        has_current_dataclip? -> current_dataclip
        true -> last_dataclip
      end

    init_form =
      if is_nil(selected_dataclip) do
        %{}
      else
        %{"manual_run" => %{dataclip_id: selected_dataclip.id}}
      end

    {:ok,
     socket
     |> assign(
       job_id: job_id,
       project: project,
       current_user: current_user,
       id: id,
       builder_state: builder_state,
       dataclips: dataclips,
       dataclips_options: dataclips_options,
       on_run: on_run,
       selected_dataclip: selected_dataclip |> format(),
       can_run_job: can_run_job,
       return_to: return_to
     )
     |> assign_new(:custom_input?, fn ->
       is_nil(selected_dataclip) && job.trigger.type in [:webhook, :cron]
     end)
     |> update_form(init_form)}
  end

  @impl true
  def handle_event(
        "confirm",
        _params,
        %{assigns: %{can_run_job: true}} = socket
      ) do
    socket.assigns.changeset
    |> Ecto.Changeset.put_change(:user, socket.assigns.current_user)
    |> create_manual_workorder()
    |> case do
      {:ok, %{attempt_run: attempt_run}} ->
        socket.assigns.on_run.(attempt_run)

        {:noreply,
         socket
         |> push_event("push-hash", %{hash: "output"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(
           changeset: changeset,
           form: Phoenix.HTML.FormData.to_form(changeset, as: "manual_run")
         )}
    end
  end

  def handle_event(
        "confirm",
        _params,
        %{assigns: %{can_run_job: false}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "You are not authorized to perform this action.")
     |> push_patch(to: socket.assigns.return_to)}
  end

  def handle_event(
        "validate",
        %{
          "manual_run" => %{"dataclip_id" => "custom"}
        } = params,
        socket
      ) do
    socket = socket |> update_form(params)

    {:noreply,
     socket |> assign(custom_input?: true, selected_dataclip: nil |> format())}
  end

  def handle_event("validate", params, socket) do
    socket = socket |> update_form(params)

    id = Ecto.Changeset.get_field(socket.assigns.changeset, :dataclip_id)

    dataclips = socket.assigns.dataclips
    selected_dataclip = Enum.find(dataclips, fn d -> d.id == id end)

    send(
      self(),
      {:update_builder_state,
       %{dataclip: selected_dataclip, job_id: socket.assigns.job_id}}
    )

    {:noreply,
     socket
     |> assign(
       custom_input?: false,
       selected_dataclip: selected_dataclip |> format()
     )}
  end

  defp format(dataclip) when is_nil(dataclip) do
    %{id: "", body: [], type: :saved_input}
  end

  defp format(dataclip) do
    %{
      id: dataclip.id,
      type: dataclip.type,
      body:
        dataclip.body
        |> Jason.encode!()
        |> Jason.Formatter.pretty_print()
        |> String.split("\n")
    }
  end

  defp update_form(socket, params) do
    manual_run = params["manual_run"] || %{}

    changeset =
      changeset(manual_run)
      |> Ecto.Changeset.put_change(:job_id, socket.assigns.job_id)
      |> Ecto.Changeset.put_change(:project_id, socket.assigns.project.id)
      |> Ecto.Changeset.put_change(:user, socket.assigns.current_user)
      |> Map.put(:action, :validate)

    socket
    |> assign(
      changeset: changeset,
      form: Phoenix.HTML.FormData.to_form(changeset, as: "manual_run")
    )
  end

  defp changeset(attrs) do
    required_fields =
      if attrs["dataclip_id"] == "custom" do
        [:body]
      else
        [:dataclip_id]
      end

    data = %{
      dataclip_id: nil,
      job_id: nil,
      project_id: nil,
      user: nil,
      body: nil,
      custom: false
    }

    types = %{
      dataclip_id: Ecto.UUID,
      job_id: Ecto.UUID,
      project_id: Ecto.UUID,
      user: :map,
      body: :string
    }

    Ecto.Changeset.cast({data, types}, attrs, required_fields)
    |> Ecto.Changeset.validate_required(required_fields)
  end

  defp create_manual_workorder(changeset) do
    with {:ok, dataclip} <- find_or_create_dataclip(changeset),
         {:ok, job} <- get_job(changeset),
         user <- changeset |> Ecto.Changeset.get_field(:user) do
      # HACK: Oban's testing functions only apply to `self` and LiveView
      # tests run in child processes, so for now we need to set the testing
      # mode from within the process.
      Process.put(:oban_testing, :manual)

      Lightning.WorkOrderService.create_manual_workorder(job, dataclip, user)
    end
  end

  defp find_or_create_dataclip(changeset) do
    dataclip_id = Ecto.Changeset.get_field(changeset, :dataclip_id)
    body = Ecto.Changeset.get_field(changeset, :body)
    project_id = Ecto.Changeset.get_field(changeset, :project_id)

    cond do
      not is_nil(dataclip_id) ->
        Lightning.Invocation.get_dataclip(dataclip_id)
        |> case do
          nil ->
            {:error,
             changeset |> Ecto.Changeset.add_error(:dataclip_id, "doesn't exist")}

          d ->
            {:ok, d}
        end

      not is_nil(body) ->
        Lightning.Invocation.create_dataclip(%{
          "project_id" => project_id,
          "type" => :run_result,
          "body" => body
        })
        |> case do
          {:error, _} ->
            {:error, changeset |> Ecto.Changeset.add_error(:body, "bad input")}

          result ->
            result
        end
    end
  end

  defp get_job(changeset) do
    changeset
    |> Ecto.Changeset.get_field(:job_id)
    |> Lightning.Jobs.get_job()
    |> case do
      nil ->
        {:error, changeset |> Ecto.Changeset.add_error(:job_id, "doesn't exist")}

      j ->
        {:ok, j}
    end
  end
end
