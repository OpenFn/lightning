[
  {"lib/lightning/task_worker.ex", :call_with_opaque},

  # PinnedAdapter pins connections to the validated IP tuples returned by
  # `Philter.Egress`, passed straight to `Mint.HTTP.connect/4` exactly as
  # `Philter.Transport` does. Mint accepts socket-address tuples at runtime
  # (exercised in pinned_adapter_test.exs), but its success typing narrows the
  # address argument to `binary()`, so dialyzer emits a spurious `:call` on the
  # connect and the `:pattern_match` / `:unused_fun` cascade that follows from
  # it. Scoped to this one file and these categories (not line-pinned, which
  # would break on any edit); Philter filters the identical warnings the same way.
  {"lib/lightning/auth_providers/oauth_http_client/pinned_adapter.ex", :call},
  {"lib/lightning/auth_providers/oauth_http_client/pinned_adapter.ex",
   :pattern_match},
  {"lib/lightning/auth_providers/oauth_http_client/pinned_adapter.ex",
   :unused_fun}
]
