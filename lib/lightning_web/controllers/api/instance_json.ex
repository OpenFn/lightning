defmodule LightningWeb.API.InstanceJSON do
  @moduledoc false

  def show(%{instance: instance}) do
    %{
      data:
        Map.update!(instance, :release, fn release ->
          Map.take(release, [:label, :commit, :image_tag, :branch])
        end)
    }
  end
end
