defmodule LightningWeb.Storybook.Form.TextField do
  use PhoenixStorybook.Story, :component
  alias LightningWeb.Components.Form

  # required
  def function, do: &Form.text_field/1

  def template do
    """
    <.form for={%{}} as={:story} :let={f} class="w-full">
      <.lsb-variation form={f}/>
    </.form>
    """
  end

  def variations do
    [
      %Variation{
        id: :default_text_input,
        attributes: %{
          field: :name
        }
      }
    ]
  end
end
