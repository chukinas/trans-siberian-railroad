[
  import_deps: [:phoenix, :typed_struct],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  export: [
    locals_without_parens: [
      handle_event: 3,
      handle_command: 3
    ]
  ],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
