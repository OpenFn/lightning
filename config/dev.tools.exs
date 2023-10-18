import Config

config :git_hooks,
  auto_install: false,
  hooks: [
    pre_commit: [
      verbose: true,
      tasks: [
        {:mix_task, :format, ["--check-formatted"]}
      ]
    ],
    pre_push: [
      verbose: true,
      tasks: [
        {:mix_task, :format, ["--check-formatted"]},
        {:mix_task, :credo, ["diff"]}
      ]
    ]
  ]
