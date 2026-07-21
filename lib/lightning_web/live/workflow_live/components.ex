defmodule LightningWeb.WorkflowLive.Components do
  @moduledoc false
  use LightningWeb, :component

  alias Phoenix.LiveView.JS

  defp humanized_auth_method_type(auth_method) do
    case auth_method do
      %{auth_type: :api} -> "API"
      %{auth_type: :basic} -> "Basic"
      _ -> ""
    end
  end

  attr :auth_methods, :list, required: true
  attr :current_user, :map, required: true
  attr :on_row_select, :any, default: nil
  attr :row_selected?, :any
  attr :class, :string, default: ""
  attr :return_to, :string
  slot :action, doc: "the slot for showing user actions in the last table column"
  slot :linked_triggers, doc: "the slot for showing the linked triggers modal"
  slot :empty_state, doc: "the slot for showing an empty state"

  def webhook_auth_methods_table(assigns) do
    assigns =
      assign(assigns,
        auth_methods:
          Lightning.Repo.preload(assigns.auth_methods, [:triggers, :project])
      )

    ~H"""
    <%= if Enum.empty?(@auth_methods) do %>
      {render_slot(@empty_state)}
    <% else %>
      <.table class={@class}>
        <:header>
          <.tr>
            <.th :if={@on_row_select} class="relative px-7 sm:w-12 sm:px-6">
              <span class="sr-only">Select</span>
            </.th>
            <.th class={"min-w-[10rem] py-2.5 text-left text-sm font-normal text-gray-900 #{!@on_row_select && "pl-4"}"}>
              Name
            </.th>
            <.th class="min-w-[7rem] py-2.5 text-left text-sm font-normal text-gray-900">
              Type
            </.th>
            <.th class="min-w-[10rem] py-2.5 text-left text-sm font-normal text-gray-900">
              Linked Triggers
            </.th>
            <.th class="min-w-[4rem] py-2.5 text-right text-sm font-normal text-gray-900">
            </.th>
          </.tr>
        </:header>
        <:body>
          <%= for auth_method <- @auth_methods do %>
            <.tr id={auth_method.id}>
              <.td :if={@on_row_select} class="relative sm:w-12 sm:px-6">
                <input
                  id={"select_#{auth_method.id}"}
                  phx-value-selection={to_string(!@row_selected?.(auth_method))}
                  type="checkbox"
                  class="absolute left-4 top-1/2 -mt-2 h-4 w-4 rounded border-gray-300 text-[#1992CC] focus:ring-indigo-600"
                  phx-click={@on_row_select.(auth_method)}
                  checked={@row_selected?.(auth_method)}
                />
              </.td>
              <.td class={"whitespace-nowrap py-2.5 text-sm text-gray-900 text-ellipsis overflow-hidden max-w-[15rem] pr-5 #{!@on_row_select && "pl-4"}"}>
                {auth_method.name}
              </.td>
              <.td class="whitespace-nowrap text-sm text-gray-900">
                <span>{humanized_auth_method_type(auth_method)}</span>
              </.td>
              <.td class="whitespace-nowrap text-sm text-gray-900">
                {render_slot(@linked_triggers, auth_method)}
              </.td>
              <.td
                :if={@action != []}
                class="text-right px-4 hover-content font-normal whitespace-nowrap py-0.5"
              >
                <div
                  :for={action <- @action}
                  class="flex items-center inline-flex gap-x-2"
                >
                  {render_slot(action, auth_method)}
                </div>
              </.td>
            </.tr>
          <% end %>
        </:body>
      </.table>
    <% end %>
    """
  end

  attr :id, :any, required: true
  attr :on_close, JS, required: true

  attr :webhook_auth_method, Lightning.Workflows.WebhookAuthMethod,
    required: true

  def linked_triggers_for_webhook_auth_method_modal(assigns) do
    assigns =
      assign(assigns,
        webhook_auth_method:
          Lightning.Repo.preload(assigns.webhook_auth_method,
            triggers: [:workflow]
          )
      )

    ~H"""
    <.modal id={@id} show={true} on_close={@on_close}>
      <:title>
        <div class="flex justify-between">
          <span>Associated Workflow Triggers</span>
          <button
            phx-click={@on_close}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="space-y-4">
        <p class="mb-4">
          You have {length(@webhook_auth_method.triggers)}
          <span class="font-semibold">Workflows</span>
          associated with the "<span class="font-semibold">My Auth</span>" authentication method:
        </p>
        <ul class="list-disc pl-5 mb-4">
          <li :for={trigger <- @webhook_auth_method.triggers} class="mb-2">
            <.link
              navigate={
                ~p"/projects/#{@webhook_auth_method.project_id}/w/#{trigger.workflow.id}?s=#{trigger.id}"
              }
              class="link"
              role="button"
              target="_blank"
            >
              {trigger.workflow.name}
            </.link>
          </li>
        </ul>
      </div>
      <:footer>
        <.button type="button" phx-click={@on_close} theme="primary">
          Close
        </.button>
      </:footer>
    </.modal>
    """
  end
end
