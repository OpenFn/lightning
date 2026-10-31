# Seeds

Scripts that fill a development database with enough data to make a performance
problem show up locally. Unlike `priv/repo/seeds.exs` and `priv/repo/demo.exs`,
nothing here is meant for everyday development - these build histories large
enough to be slow, and they take a while to run.

- `export_load.exs` - a project with a large work order history, for the history
  export. Every dimension is tunable with env vars; see the comment at the top
  of the file.
