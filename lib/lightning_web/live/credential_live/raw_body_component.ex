defmodule LightningWeb.CredentialLive.RawBodyComponent do
  use LightningWeb, :component

  attr :form, :map, required: true
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    assigns = assigns |> assign(valid?: changeset.valid?)

    ~H"""
    {render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &inner/1,
         [form: @form],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    )}
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
        <.input type="codearea" field={@form[:body]} />
      </div>
    </fieldset>
    """
  end
end
