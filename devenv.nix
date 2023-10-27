{ pkgs, ... }:

{
  packages = [ pkgs.pyright pkgs.black pkgs.ruff ];

  # https://devenv.sh/languages/
  languages.python.enable = true;
  languages.python.version = "3.11";
  languages.python.poetry.enable = true;
}
