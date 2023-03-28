defmodule LightningWeb.Storybook.Cards.Card do
  alias LightningWeb.Components.Cards
  use PhoenixStorybook.Story, :component

  # required
  def function, do: &Cards.card/1

  def variations do
    [
      %Variation{
        id: :default,
        description: "Default",
        attributes: %{},
        slots: [
          """
          <h3 class="text-sm font-medium text-gray-900">My Workflow</h3>
          """
        ]
      },
      %Variation{
        id: :with_actions,
        description: "With Actions",
        attributes: %{},
        slots: [
          """
          Workflow Name
          """,
          """
          <:action>
            <a class="relative -mr-px inline-flex w-0 flex-1 items-center justify-center gap-x-2 py-2 text-sm">
              <Heroicons.pencil_square class="h-4 w-4" />
              Edit
            </a>
          </:action>
          """,
          """
          <:action>
            <a class="relative -mr-px inline-flex w-0 flex-1 items-center justify-center gap-x-2 py-2 text-sm">
              <Heroicons.trash class="h-4 w-4" />
              Delete
            </a>
          </:action>
          """
        ]
      },
      %Variation{
        id: :linkable,
        description: "With a link",
        attributes: %{},
        slots: [
          """
          <.link navigate="/">Workflow Name</.link>
          """
        ]
      }
    ]
  end
end
