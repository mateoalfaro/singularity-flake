{ pkgs, nixpkgs }:

pkgs.buildGoModule rec {
  pname = "vetro";
  version = "0-unstable-2026-06-05";

  src = pkgs.fetchFromGitHub {
    owner = "singularityos-lab";
    repo = "vetro";
    rev = "0a7bd367676f67e1c15a304ba135fe6fecdbc604";
    hash = "sha256-BxAmyP6IqmqHEBmxKIRw0QMt14y/0CMOUab546xVYyQ=";
  };

  vendorHash = "sha256-BKIYil3eWmwqIUf/46LY426uBN7qrVaqWX3YvODj8gc=";

  # Names that already start with "Singularity" are fully-qualified GObject
  # type names; return them unchanged instead of prefixing "Gtk".
  postPatch = ''
    substituteInPlace internal/domain/vetro/utils.go \
      --replace-fail \
        $'\treturn gtkClassPrefix + name' \
        $'\tif strings.HasPrefix(name, "Singularity") {\n\t\treturn name\n\t}\n\treturn gtkClassPrefix + name'
  '';

  meta = {
    description = "Declarative GTK4 UI transpiler";
    homepage = "https://github.com/singularityos-lab/vetro";
    license = nixpkgs.lib.licenses.mit;
  };
}
