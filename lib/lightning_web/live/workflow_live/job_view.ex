defmodule LightningWeb.WorkflowLive.JobView do
  use LightningWeb, :component
  alias LightningWeb.WorkflowLive.EditorPane

  import LightningWeb.WorkflowLive.Components

  attr :id, :string, required: true
  slot :top

  slot :inner_block, required: false

  slot :bottom

  def container(assigns) do
    ~H"""
    <div class="relative h-full flex bg-white" id={@id}>
      <div class="grow flex min-h-full flex-col">
        <div class="h-14 relative">
          <%= render_slot(@top) %>
        </div>
        <!-- 3 column wrapper -->
        <div class="grow flex h-5/6 gap-3">
          <%= render_slot(@inner_block) %>
        </div>
        <div class="h-14 flex p-2 justify-end">
          <%= render_slot(@bottom) %>
        </div>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true
  attr :class, :string, default: ""
  attr :id, :string, required: true

  defp column(assigns) do
    ~H"""
    <div id={@id} class={["flex-1 shrink px-4 pt-4 collapsible-panel", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :job, :map, required: true
  attr :form, :map, required: true, doc: "A form built from a job"
  attr :current_user, :map, required: true
  attr :project, :map, required: true
  attr :close_url, :any, required: true
  attr :socket, :any, required: true
  attr :follow_run_id, :any, default: nil

  slot :footer

  slot :collapsible_panel do
    attr :id, :string, required: true
    attr :panel_title, :string, required: true
    attr :class, :string, doc: "Extra CSS classes for the column"
  end

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
              <.link patch={@close_url}>
                <Heroicons.x_mark class="w-6 h-6 text-gray-500 hover:text-gray-700 hover:cursor-pointer" />
              </.link>
            </div>
          </div>
        </div>
      </:top>
      <%= for slot <- @collapsible_panel do %>
        <.collapsible_panel
          id={slot[:id]}
          panel_title={slot[:panel_title]}
          class={"#{slot[:class]} h-full border"}
        >
          <%= render_slot(slot) %>
        </.collapsible_panel>
      <% end %>
      <.collapsible_panel
        id={"job-editor-pane-#{@job.id}"}
        class="h-full border"
        panel_title="Editor"
      >
        <.live_component
          module={EditorPane}
          id={"job-editor-pane-#{@job.id}"}
          form={@form}
          disabled={false}
          class="h-full pb-16 border"
        />
      </.collapsible_panel>
      <.collapsible_panel id="output-logs" panel_title="Output & Logs" class="border">
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
            <div class="text-gray-500 pb-2">
              After you click run, the logs and output will be visible here.
            </div>
          </div>
        <% end %>
      </.collapsible_panel>
      <:bottom>
        <%= render_slot(@footer) %>
      </:bottom>
    </.container>
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
