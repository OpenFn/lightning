defmodule LightningWeb.RunLive.WorkOrderLoading do
  @moduledoc """
  Workorder loading component
  """
  use LightningWeb, :component

  def filler(assigns) do
    ~H"""
    <div data-entity="work_order" role="rowgroup" class="bg-gray-50 animate-pulse">
      <div role="row" class="grid grid-cols-8 items-center">
        <div
          role="cell"
          class="col-span-3 py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
        >
          <div
            class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
            role="cell"
          >
            --
          </div>
          <div
            class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
            role="cell"
          >
            --
          </div>
          <div
            class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
            role="cell"
          >
            --
          </div>
          <div
            class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
            role="cell"
          >
            --
          </div>
        </div>
      </div>
    </div>
    """
  end
end
