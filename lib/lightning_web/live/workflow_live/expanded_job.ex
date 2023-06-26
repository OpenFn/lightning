defmodule LightningWeb.WorkflowLive.ExpandedJobModal do
  use LightningWeb, :live_component

  alias Lightning.Jobs.Job

  @impl true
  def update(%{job: job} = assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen overscroll-none">
      <div class="grid grid-cols-3 divide-x h-1/6">
        <span><%= @job.adaptor %></span>
        <span>
          <%= if @job.credential != nil do %>
            <%= @job.credential.name %>
          <% else %>
            <%= "No Credentials" %>
          <% end %>
        </span>
        <span><%= @job.name %></span>
      </div>
      <div class="h-5/6">
        <div class="h-5/6">
          <span> Runs View </span>
        </div>
        <div class="h-1/6">
          <span> Reruns  Buttons </span>
        </div>
      </div>
    </div>
    """
  end
end
