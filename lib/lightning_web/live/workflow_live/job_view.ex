defmodule LightningWeb.WorkflowLive.JobView do
  use LightningWeb, :component
  alias LightningWeb.WorkflowLive.EditorPane

  attr :id, :string, required: true
  slot :top

  slot :column do
    attr :class, :string, doc: "Extra CSS classes for the column"
  end

  slot :bottom

  def container(assigns) do
    ~H"""
    <div class="relative h-full flex bg-white" id={@id}>
      <div class="grow flex min-h-full flex-col ">
        <div class="h-14 border-b relative">
          <%= render_slot(@top) %>
        </div>
        <!-- 3 column wrapper -->
        <div class="grow flex">
          <%= for slot <- @column do %>
            <div class={"flex-1 px-4 py-6 #{Map.get(slot, :class, "")}"}>
              <%= render_slot(slot) %>
            </div>
          <% end %>
        </div>
        <div class="h-14 flex border-t">
          <%= render_slot(@bottom) %>
        </div>
      </div>
    </div>
    """
  end

  attr :job, :map, required: true
  attr :form, :map, required: true
  attr :current_user, :map, required: true
  attr :project, :map, required: true
  attr :close_url, :any, required: true
  attr :socket, :any, required: true
  attr :on_run, :any, required: true, doc: "Callback to run a job manually"
  attr :follow_run_id, :any, default: nil

  def job_edit_view(assigns) do
    ~H"""
    <.container id={"job-edit-view-#{@job.id}"}>
      <:top>
        <div class="flex h-14 place-content-stretch">
          <div class="basis-1/3 flex items-center gap-4 pl-4">
            <.adaptor_block adaptor={@job.adaptor} />
            <.credential_block credential={@job.credential} />
          </div>
          <div class="basis-1/3 font-semibold flex items-center justify-center">
            <%= @job.name %>
          </div>
          <div class="basis-1/3 flex justify-end">
            <div class="flex w-14 items-center justify-center">
              <.link href={@close_url}>
                <Heroicons.x_mark class="w-6 h-6 text-gray-500 hover:text-gray-700 hover:cursor-pointer" />
              </.link>
            </div>
          </div>
        </div>
      </:top>
      <:column>
        <.input_pane
          job={@job}
          on_run={@on_run}
          user={@current_user}
          project={@project}
        />
      </:column>
      <:column class="h-full">
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
      </:column>
      <:column>
        <!-- Right column area -->
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
          </div>
        <% end %>
      </:column>
    </.container>
    """
  end

  attr :job, :map, required: true
  attr :user, :map, required: true
  attr :project, :map, required: true
  attr :on_run, :any, required: true, doc: "Callback to run a job manually"
  attr :can_run_job, :boolean, default: true

  def input_pane(%{job: job} = assigns) do
    assigns =
      if changed?(assigns, :job) do
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
        project={@project}
        user={@user}
        on_run={@on_run}
        can_run_job={@can_run_job}
      />
    <% else %>
      <p>Please save your Job first.</p>
    <% end %>
    """
  end

  defp credential_block(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%= if @credential do %>
        <Heroicons.lock_closed class="w-6 h-6 text-gray-500" />
        <span class="text-xs text-gray-500 font-semibold grow">
          <%= @credential.name %>
        </span>
      <% else %>
        <Heroicons.lock_open class="w-6 h-6 text-gray-500" />
        <span class="text-xs text-gray-500 font-semibold grow">
          No Credential
        </span>
      <% end %>
    </div>
    """
  end

  defp adaptor_block(assigns) do
    {package_name, version} =
      Lightning.AdaptorRegistry.resolve_package_name(assigns.adaptor)

    assigns =
      assigns
      |> assign(
        package_name: package_name,
        version: version
      )

    ~H"""
    <div class="grid grid-rows-2 grid-flow-col">
      <div class="row-span-2 flex items-center mr-2">
        <Heroicons.cube class="w-6 h-6 text-gray-500" />
      </div>
      <div class="text-xs text-gray-500 font-semibold">
        <%= @package_name %>
      </div>
      <div class="text-xs text-gray-500 font-semibold font-mono">
        <%= @version %>
      </div>
    </div>
    """
  end
end
