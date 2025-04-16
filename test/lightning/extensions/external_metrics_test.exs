defmodule Lightning.Extensions.ExternalMetricsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Extensions.ExternalMetrics

  test "returns an empty list " do
    assert ExternalMetrics.plugins() == []
  end
end
