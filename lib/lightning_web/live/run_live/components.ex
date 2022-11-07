defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  use LightningWeb, :component

  def failure_pill(assigns) do
    ~H"""
    <span class="text-green-red my-auto whitespace-nowrap rounded-full bg-red-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-red-800">
      Failure
    </span>
    """
  end

  def success_pill(assigns) do
    ~H"""
    <span class="my-auto whitespace-nowrap rounded-full bg-green-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-green-800">
      Success
    </span>
    """
  end

  def pending_pill(assigns) do
    ~H"""
    <span class="my-auto whitespace-nowrap rounded-full bg-grey-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-grey-800">
      Pending
    </span>
    """
  end
end
