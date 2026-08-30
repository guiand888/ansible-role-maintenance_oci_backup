{
  description = "guiand888 Ansible role dev toolchain";

  inputs = {
    # Pinned to the exact commit this entire role corpus was gate-tested
    # against (ansible-core 2.21.2, ansible bundle 14.2.0, ansible-lint
    # 25.8.2, Python 3.14.7, ansible.posix 2.2.2, community.general 13.2.0)
    # rather than tracking the nixos-unstable branch, so `nix flake update`
    # can no longer silently drift the toolchain out from under a role that
    # was verified to work against these exact versions. To move forward
    # deliberately later: bump this rev, re-run the full gate suite on all
    # 15 roles, re-freeze MANIFEST.sha256.
    nixpkgs.url = "github:NixOS/nixpkgs/0e251e24a4f24e036a084b6b4b2d2491af4167f4";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # The full `ansible` bundle, not bare `ansible-core`: several roles
        # in this family (system_swap, zram_optimization_vm, system_firewall,
        # ssh_keys, swapiness) use ansible.posix and/or community.general
        # modules, and ansible-core alone does not ship them. Declaring the
        # full bundle here makes that resolution deliberate rather than an
        # accident of some other package's transitive closure (verified: on
        # a bare ansible-core shell, ansible.posix was reachable ONLY because
        # nixpkgs' ansible-lint happens to depend on the full ansible
        # collection set for its own schema/doc data — not something to rely
        # on). Deliberately NOT the full ansible-gafr toolchain otherwise: no
        # openstacksdk/docker/netaddr/websocket-client/age/sops — none of
        # those are used by a standalone role repo. `oci` below is the one
        # deliberate exception to that rule; see its own comment.
        pythonForAnsible = pkgs.python3.withPackages (ps: with ps; [
          ansible
          jmespath
          # Deliberate deviation from the scaffold's usual policy of
          # excluding SDKs (see other roles' flake.nix comments): this is
          # the one role in the corpus that calls a cloud API needing an
          # SDK on the controller. The `oracle.oci` Ansible collection's
          # modules run delegate_to: localhost and require the `oci` SDK
          # importable by that Python interpreter — there is no pure-FQCN
          # path around it. Pinned nixpkgs revision above carries
          # python3Packages.oci 2.165.1. `oci` is also added to
          # ansible-gafr's flake.nix for the same reason when this role is
          # consumed there.
          oci
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          name = "ansible-role";

          packages = [
            pythonForAnsible
            pkgs.ansible-lint
            pkgs.yamllint
            pkgs.pre-commit
            pkgs.gitleaks
          ];

          shellHook = ''
            # Several ANSIBLE_* env vars take precedence over ansible.cfg and
            # have been found set in Guillaume's shell pointing at stale/
            # renamed paths (e.g. ANSIBLE_ROLES_PATH -> a path that no longer
            # exists) — unset them here so the repo behaves the same
            # regardless of the calling shell's history. No ANSIBLE_CONFIG
            # export here: unlike ansible-gafr this is a role repo, not a
            # playbook/inventory repo, and ansible.cfg's `roles_path` is what
            # lets tests/test.yml resolve `guiand888.<name>` against this
            # checkout — see tests/test.yml and ansible.cfg.
            unset ANSIBLE_ROLES_PATH ANSIBLE_INVENTORY ANSIBLE_COLLECTIONS_PATH
            echo "ansible role dev shell: $(ansible --version | head -n1)"
          '';
        };
      });
}
