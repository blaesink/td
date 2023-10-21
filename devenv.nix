{ pkgs, ... }:

{
  # https://devenv.sh/basics/
  env.GREET = "devenv";

  packages = [ pkgs.pyright pkgs.black pkgs.ruff ];

  # https://devenv.sh/scripts/
  scripts.hello.exec = "echo hello from $GREET";

  enterShell = ''
    hello
  '';

  # https://devenv.sh/languages/
  languages.python.enable = true;
  languages.python.version = "3.11";
  languages.python.poetry.enable = true;

  # https://devenv.sh/pre-commit-hooks/
  # pre-commit.hooks.shellcheck.enable = true;

  # https://devenv.sh/processes/
  # processes.ping.exec = "ping example.com";

  # See full reference at https://devenv.sh/reference/options/
}
