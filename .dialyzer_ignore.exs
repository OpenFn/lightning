[
  # `task_worker.ex` needed a skip here until `flags: [:no_opaque]` in mix.exs
  # covered it. Restore it if that flag goes.
  {"lib/lightning/auth_providers/well_known.ex", :invalid_contract},
  {"lib/mix/tasks/install_schemas.ex", :invalid_contract},

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

  # PinnedAdapter hands Mint a validated IP tuple, and Mint's typespecs cannot
  # see that connect succeeding, so what follows it looks unreachable. mint
  # 1.10.0 widened `Mint.Core.Util.hostname/2`, which turned that from a
  # `:call` and its cascade into an opacity complaint about `Mint.HTTP.t()`
  # being a plain union of opaque types. Upstream typespec bug, so drop this if
  # it is fixed. Philter filters the same warnings. Detail in #5117.
  {"lib/lightning/auth_providers/oauth_http_client/pinned_adapter.ex",
   :call_with_opaque},
  {"lib/lightning/auth_providers/oauth_http_client/pinned_adapter.ex",
   :no_return, 80}
]
