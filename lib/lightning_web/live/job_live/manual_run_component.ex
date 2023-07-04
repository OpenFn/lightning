defmodule LightningWeb.JobLive.ManualRunComponent do
  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  attr :job, :map, required: true
  attr :on_run, :any, required: true
  attr :selected_dataclip, Lightning.Invocation.Dataclip

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
        as={:manual_run}
        phx-target={@myself}
        phx-change="validate"
        class="h-full flex flex-col"
      >
        <%= error_tag(f, :dataclip_id) %>
        <Form.select_field
          form={f}
          name={:dataclip_id}
          values={@dataclips_options}
          phx-target={@myself}
          phx-change="validate"
        />
        <br />
        <div class="flex flex-col gap-2">
          <div class="flex gap-4 flex-row text-sm">
            <div class="basis-1/2 font-semibold text-secondary-700">
              Dataclip Type
            </div>
            <div class="basis-1/2 text-right">
              <Common.dataclip_type_pill dataclip={@selected_dataclip} />
            </div>
          </div>
          <div class="flex gap-4 flex-row text-sm">
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
          id: id,
          job: job,
          dataclips: dataclips,
          on_run: on_run,
          can_run_job: can_run_job
        },
        socket
      ) do
    dataclips_options =
      dataclips
      |> Enum.map(&{&1.id, &1.id})
      |> Enum.concat([{"New custom input", "custom"}])

    selected_dataclip =
      socket.assigns |> Map.get(:selected_dataclip, dataclips |> List.first())

    {:ok,
     socket
     |> assign(
       can_run_job: can_run_job,
       changeset: changeset(%{}),
       dataclips: dataclips,
       dataclips_options: dataclips_options,
       id: id,
       job: job,
       on_run: on_run,
       selected_dataclip: selected_dataclip
     )
     |> assign_new(:custom_input?, fn ->
       is_nil(selected_dataclip)
     end)}
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
        {:noreply, socket |> assign(changeset: changeset)}
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
    {:noreply,
     socket
     |> assign(
       changeset: changeset(params) |> Map.put(:action, :validate),
       custom_input?: true,
       selected_dataclip: nil |> format()
     )}
  end

  def handle_event("validate", params, socket) do
    socket = socket |> update_form(params)

    id = Ecto.Changeset.get_field(socket.assigns.changeset, :dataclip_id)

    dataclips = socket.assigns.dataclips
    selected_dataclip = Enum.find(dataclips, fn d -> d.id == id end)

    # send(
    #   self(),
    #   {:update_builder_state,
    #    %{dataclip: selected_dataclip, job_id: socket.assigns.job_id}}
    # )

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
      |> Map.put(:action, :validate)

    socket
    |> assign(changeset: changeset)
  end

  defp changeset(attrs) do
    # required_fields =
    #   if attrs["body"] == "custom" or attrs == %{} do
    #     [:body]
    #   else
    #     [:dataclip_id]
    #   end

    data = %{
      dataclip_id: nil,
      body: nil
    }

    types = %{
      dataclip_id: Ecto.UUID,
      body: :string
    }

    # , required_fields)
    Ecto.Changeset.cast({data, types}, attrs, [:dataclip_id, :body])
    # |> Ecto.Changeset.validate_required(required_fields)
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
