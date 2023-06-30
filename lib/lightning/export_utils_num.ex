defmodule Lightning.ExportUtilsNum do
  @moduledoc """
  A convience module for setting up and using ex_cldr when converting numbers to
  their strings for use in our yaml
  """
  use Cldr,
    locales: [:en],
    providers: [Cldr.Number]
end
