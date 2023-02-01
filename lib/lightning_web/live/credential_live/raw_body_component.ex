defmodule LightningWeb.CredentialLive.RawBodyComponent do
  use LightningWeb, :component

  def fieldset(assigns) do
    changeset = assigns.form.source

    assigns = assigns |> assign(valid?: changeset.valid?)

    ~H"""
    <%= render_slot(
      @inner_block,
      {Phoenix.LiveView.HTMLEngine.component(
         &inner/1,
         [form: @form],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    ) %>
    """
  end

  defp inner(assigns) do
    ~H"""
    <fieldset>
      <legend class="contents text-base font-medium text-gray-900">
        Details
      </legend>
      <p class="text-sm text-gray-500">
        Configuration for this credential.
      </p>

      <div class="text-right">
        <span class="text-sm text-secondary-700">
          Required
        </span>
      </div>
      <div>
        <%= error_tag(@form, :body, class: "block w-full rounded-md") %>
        <%= textarea(@form, :body,
          class: "rounded-md w-full font-mono bg-slate-800 text-slate-100"
        ) %>
      </div>
    </fieldset>
    """
  end
end
