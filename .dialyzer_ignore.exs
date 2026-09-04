[
  {"lib/lightning/task_worker.ex", :call_with_opaque},
  {"lib/lightning/auth_providers/well_known.ex", :invalid_contract},

  # httpoison 3.0.0 typespec bug, surfaced by hackney 4. Hackney 4 moved to a
  # process-per-connection design, so a client handle is now a pid where it used
  # to be a reference -- but `HTTPoison.AsyncResponse.t()` still declares
  # `id: reference()`. Every module that does `use HTTPoison.Base` therefore
  # trips the `stream_next/1` callback contract, and dialyzer attributes the
  # warning to the macro's own source rather than to ours. The trailing
  # `pattern_match_cov` is a dead clause in httpoison's `process_response/1`.
  # Filtered by category rather than line so a 3.0.x patch bump doesn't break
  # the filter; this is a dependency's source, so it cannot mask our own bugs.
  #
  # Already fixed upstream in edgurgel/httpoison#511 ("Fix typespec warnings",
  # merged 2026-07-05), which retypes these as `id: pid` and drops the dead
  # clause. It is just unreleased: 3.0.0 (2026-06-14) predates the merge and is
  # still the latest release. Drop all three filters once a release carries it.
  {"deps/httpoison/lib/httpoison/base.ex", :callback_arg_type_mismatch},
  {"deps/httpoison/lib/httpoison/base.ex", :callback_type_mismatch},
  {"deps/httpoison/lib/httpoison/base.ex", :pattern_match_cov},

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
