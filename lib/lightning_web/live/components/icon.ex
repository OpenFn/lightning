defmodule LightningWeb.Components.Icon do
  @moduledoc """
  SVG Icons
  """
  use LightningWeb, :component

  def project_setting(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        d="M8.32463 2.31731C8.75103 0.560897 11.249 0.560897 11.6754 2.31731C11.9508 3.45193 13.2507 3.99038 14.2478 3.38285C15.7913 2.44239 17.5576 4.2087 16.6172 5.75218C16.0096 6.74925 16.5481 8.04918 17.6827 8.32463C19.4391 8.75103 19.4391 11.249 17.6827 11.6754C16.5481 11.9508 16.0096 13.2507 16.6172 14.2478C17.5576 15.7913 15.7913 17.5576 14.2478 16.6172C13.2507 16.0096 11.9508 16.5481 11.6754 17.6827C11.249 19.4391 8.75103 19.4391 8.32463 17.6827C8.04918 16.5481 6.74926 16.0096 5.75219 16.6172C4.2087 17.5576 2.44239 15.7913 3.38285 14.2478C3.99038 13.2507 3.45193 11.9508 2.31731 11.6754C0.560897 11.249 0.560897 8.75103 2.31731 8.32463C3.45193 8.04918 3.99037 6.74926 3.38285 5.75218C2.44239 4.2087 4.2087 2.44239 5.75219 3.38285C6.74926 3.99037 8.04918 3.45193 8.32463 2.31731Z"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M13 10C13 11.6569 11.6569 13 10 13C8.34315 13 7 11.6569 7 10C7 8.34315 8.34315 7 10 7C11.6569 7 13 8.34315 13 10Z"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </.outer_svg>
    """
  end

  def dataclips(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        d="M11.1213 11.1213L16 16M9 9L16 2M9 9L6.12132 11.8787M9 9L6.12132 6.12132M6.12132 11.8787C5.57843 11.3358 4.82843 11 4 11C2.34315 11 1 12.3431 1 14C1 15.6569 2.34315 17 4 17C5.65685 17 7 15.6569 7 14C7 13.1716 6.66421 12.4216 6.12132 11.8787ZM6.12132 6.12132C6.66421 5.57843 7 4.82843 7 4C7 2.34315 5.65685 1 4 1C2.34315 1 1 2.34315 1 4C1 5.65685 2.34315 7 4 7C4.82843 7 5.57843 6.66421 6.12132 6.12132Z"
        stroke-linecap="round"
      />
    </.outer_svg>
    """
  end

  def runs(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        d="M1.99998 4.12141C1.99998 4.52773 2.24584 4.89366 2.62203 5.04724C2.99821 5.20081 3.42992 5.11148 3.71428 4.82124C5.05811 3.44961 6.92831 2.5999 8.99998 2.5999C12.222 2.5999 14.963 4.65908 15.9788 7.53325C16.0157 7.6374 15.9611 7.75166 15.8569 7.78847C15.7528 7.82528 15.6385 7.7707 15.6017 7.66655C14.6405 4.94708 12.0471 2.9999 8.99998 2.9999C6.71045 2.9999 4.67574 4.10054 3.39966 5.79929C3.17208 6.10225 3.13528 6.5078 3.3046 6.84678C3.47392 7.18575 3.82029 7.3999 4.1992 7.3999H7.79998C7.91043 7.3999 7.99998 7.48945 7.99998 7.5999C7.99998 7.71036 7.91043 7.7999 7.79998 7.7999H1.79998C1.68952 7.7999 1.59998 7.71036 1.59998 7.5999V1.5999C1.59998 1.48945 1.68952 1.3999 1.79998 1.3999C1.91043 1.3999 1.99998 1.48945 1.99998 1.5999V4.12141ZM14.6003 14.2005C14.8279 13.8976 14.8647 13.492 14.6953 13.153C14.526 12.8141 14.1797 12.5999 13.8008 12.5999L10.2 12.5999C10.0895 12.5999 9.99998 12.5104 9.99998 12.3999C9.99998 12.2894 10.0895 12.1999 10.2 12.1999H16.2C16.253 12.1999 16.3039 12.221 16.3414 12.2585C16.3789 12.296 16.4 12.3469 16.4 12.3999V18.3999C16.4 18.5104 16.3104 18.5999 16.2 18.5999C16.0895 18.5999 16 18.5104 16 18.3999V15.8784C16 15.4721 15.7541 15.1061 15.3779 14.9526C15.0017 14.799 14.57 14.8883 14.2857 15.1786C12.9418 16.5502 11.0716 17.3999 8.99998 17.3999C5.77797 17.3999 3.03697 15.3407 2.0211 12.4666C1.98429 12.3624 2.03888 12.2481 2.14302 12.2113C2.24716 12.1745 2.36143 12.2291 2.39824 12.3333C3.35943 15.0527 5.95288 16.9999 8.99998 16.9999C11.2895 16.9999 13.3242 15.8993 14.6003 14.2005Z"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </.outer_svg>
    """
  end

  def workflows(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        d="M1 3C1 1.89543 1.89543 1 3 1H5C6.10457 1 7 1.89543 7 3V5C7 6.10457 6.10457 7 5 7H3C1.89543 7 1 6.10457 1 5V3Z"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M11 3C11 1.89543 11.8954 1 13 1H15C16.1046 1 17 1.89543 17 3V5C17 6.10457 16.1046 7 15 7H13C11.8954 7 11 6.10457 11 5V3Z"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M1 13C1 11.8954 1.89543 11 3 11H5C6.10457 11 7 11.8954 7 13V15C7 16.1046 6.10457 17 5 17H3C1.89543 17 1 16.1046 1 15V13Z"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M11 13C11 11.8954 11.8954 11 13 11H15C16.1046 11 17 11.8954 17 13V15C17 16.1046 16.1046 17 15 17H13C11.8954 17 11 16.1046 11 15V13Z"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </.outer_svg>
    """
  end

  def logout(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
      />
    </.outer_svg>
    """
  end

  def left(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M11 17l-5-5m0 0l5-5m-5 5h12"
      />
    </.outer_svg>
    """
  end

  def right(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M13 7l5 5m0 0l-5 5m5-5H6"
      />
    </.outer_svg>
    """
  end

  def trash(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
      />
    </.outer_svg>
    """
  end

  def plus(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
    </.outer_svg>
    """
  end

  def archive(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"
      />
    </.outer_svg>
    """
  end

  def cog(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <circle cx="12" cy="12" r="3"></circle>
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z">
      </path>
    </.outer_svg>
    """
  end

  def user(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path d="M12.075,10.812c1.358-0.853,2.242-2.507,2.242-4.037c0-2.181-1.795-4.618-4.198-4.618S5.921,4.594,5.921,6.775c0,1.53,0.884,3.185,2.242,4.037c-3.222,0.865-5.6,3.807-5.6,7.298c0,0.23,0.189,0.42,0.42,0.42h14.273c0.23,0,0.42-0.189,0.42-0.42C17.676,14.619,15.297,11.677,12.075,10.812 M6.761,6.775c0-2.162,1.773-3.778,3.358-3.778s3.359,1.616,3.359,3.778c0,2.162-1.774,3.778-3.359,3.778S6.761,8.937,6.761,6.775 M3.415,17.69c0.218-3.51,3.142-6.297,6.704-6.297c3.562,0,6.486,2.787,6.705,6.297H3.415z">
      </path>
    </.outer_svg>
    """
  end

  def warning(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
      />
    </.outer_svg>
    """
  end

  def eye(assigns) do
    ~H"""
    <.outer_svg {assigns}>
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
      />
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
      />
    </.outer_svg>
    """
  end

  def chevron_left(assigns) do
    ~H"""
    <svg
      class="h-5 w-5"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
    >
      <path
        fill-rule="evenodd"
        d="M12.707 5.293a1 1 0 010 1.414L9.414 10l3.293 3.293a1 1 0 01-1.414 1.414l-4-4a1 1 0 010-1.414l4-4a1 1 0 011.414 0z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  def chevron_right(assigns) do
    ~H"""
    <svg
      class="h-5 w-5"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
    >
      <path
        fill-rule="evenodd"
        d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp outer_svg(assigns) do
    default_classes = ~w[h-5 w-5 inline-block]
    attrs = build_attrs(assigns, default_classes)

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      stroke-width="2"
      {attrs}
    >
      <%= render_slot(@inner_block) %>
    </svg>
    """
  end

  defp build_attrs(assigns, default_classes) do
    assigns
    |> Map.put_new(:class, default_classes)
    |> assigns_to_attributes()
  end
end
