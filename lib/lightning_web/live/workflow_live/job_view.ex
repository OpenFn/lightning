defmodule LightningWeb.WorkflowLive.JobView do
  use LightningWeb, :component
  alias LightningWeb.WorkflowLive.EditorPane

  attr :job, :map, required: true
  attr :form, :map, required: true
  attr :on_close, :any, required: true

  def job_edit_view(assigns) do
    ~H"""
    <div class="relative h-full flex bg-white" id={"job-edit-view-#{@job.id}"}>
      <div class="grow flex min-h-full flex-col ">
        <!-- Top band -->
        <div class="h-14 flex border-b">
          <div class="grow"></div>
          <div
            class="grow-0 w-14 flex items-center justify-center"
            phx-click={@on_close}
            phx-value-show="false"
          >
            <Heroicons.x_mark class="w-6 h-6 text-gray-500 hover:text-gray-700 hover:cursor-pointer" />
          </div>
        </div>
        <!-- 3 column wrapper -->
        <div class="grow flex">
          <div class="flex-1 px-4 py-6">
            <!-- Left column area -->
            <.input_pane id={"job-input-pane-#{@job.id}"} job={@job} />
          </div>

          <div class="flex-1 px-4 py-6 h-full">
            <!-- Main area -->
            <.live_component
              module={EditorPane}
              id={"job-editor-pane-#{@job.id}"}
              form={
                @form
                |> inputs_for(:jobs)
                |> Enum.find(&(Ecto.Changeset.get_field(&1.source, :id) == @job.id))
              }
              disabled={false}
              class="h-full"
            />
          </div>

          <div class="flex-1 px-4 py-6">
            <!-- Right column area -->
            Right
          </div>
        </div>
        <!-- Top band -->
        <div class="h-14 flex border-t">
          bottom band
        </div>
      </div>
    </div>
    """
  end

  def input_pane(%{job: job} = assigns) do
    assigns =
      if changed?(assigns, :job) do
        # TODO: this might end up triggering constant reloading
        assign(assigns,
          dataclips:
            Lightning.Invocation.list_dataclips_for_job(%Lightning.Jobs.Job{
              id: job.id
            })
        )
      else
        assigns |> assign_new(:dataclips, fn -> [] end)
      end
      |> assign(is_persisted: job.__meta__.state == :loaded)

    ~H"""
    <%= if @is_persisted do %>
      <.live_component
        module={LightningWeb.JobLive.ManualRunComponent}
        id={"manual-job-#{@job.id}"}
        job={@job}
        dataclips={@dataclips}
        on_run={fn attempt_run -> follow_run(@job_id, attempt_run) end}
        builder_state={%{}}
        can_run_job={true}
      />
    <% else %>
      <p>Please save your Job first.</p>
    <% end %>
    """
  end

  def follow_run(job_id, attempt_run) do
    IO.inspect({job_id, attempt_run})
    # send_update(__MODULE__,
    #   id: id(job_id),
    #   attempt_run: attempt_run,
    #   event: :follow_run
    # )
  end
end
