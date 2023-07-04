defmodule LightningWeb.WorkflowLive.JobView do
  use LightningWeb, :component
  alias LightningWeb.WorkflowLive.EditorPane

  attr :job, :map, required: true
  attr :form, :map, required: true
  attr :on_close, :any, required: true

  def job_edit_view(assigns) do
    ~H"""
    <div class="relative h-full flex bg-white">
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
            <div class="rounded-md border border-dashed border-gray-700">
              Left
            </div>
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
end
