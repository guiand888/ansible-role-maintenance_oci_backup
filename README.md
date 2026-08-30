maintenance_oci_backup
=======================

# Purpose
Take a monthly, gate-quality Oracle Cloud Infrastructure (OCI) backup of a compute instance's boot volume and (optionally) every block volume attached to it, verify the backup actually exists and is `AVAILABLE` before reporting success, and optionally prune this role's own backups on a retention window so manual backups (which never expire on their own) don't bill indefinitely.

# Features
- Materializes a vault-supplied OCI API signing key to a permission-locked (`0600`) temp file on the controller for the duration of the run, and always removes it afterward - even on failure.
- Discovers the instance's boot volume and attached block volumes via `oracle.oci` facts modules; a zero-result discovery fails loudly rather than backing up nothing.
- Creates a date-stamped, `INCREMENTAL` boot volume backup and (opt-out) one date-stamped backup per attached block volume, using the OCI modules' native idempotency (never `force_create`) so a same-day retry cannot mint duplicate billable backups.
- Re-fetches every backup it just created by its exact expected name and asserts it is in `AVAILABLE` state - a silently skipped create cannot report success.
- Optional, opt-in, compartment-scoped pruning of backups whose name starts with `maintenance_oci_backup_name_prefix` and are older than `maintenance_oci_backup_retention_days`, with a dry-run mode on by default.
- All OCI API calls run `delegate_to: localhost` / `become: false` - the API call is always made from the controller, never the managed host.

# Instructions

## Required Variables

| Variable | Description |
|---|---|
| `maintenance_oci_backup_compartment_id` | OCID of the compartment the instance and its backups live in. Required whenever the role does anything (backup or prune). |
| `maintenance_oci_backup_tenancy` | OCI tenancy OCID. Required whenever the role does anything. |
| `maintenance_oci_backup_region` | OCI region identifier (e.g. `eu-frankfurt-1`). Required whenever the role does anything. |
| `maintenance_oci_backup_api_user` | OCID of the API user. Required whenever the role does anything. |
| `maintenance_oci_backup_api_user_fingerprint` | Fingerprint of the API signing key. Required whenever the role does anything. |
| `maintenance_oci_backup_api_user_key_content` | PEM-formatted API signing key content (not a path - see `tasks/auth.ansible.yml`). Expected to arrive vault-encrypted from the caller. Required whenever the role does anything. |
| `maintenance_oci_backup_instance_id` | OCID of the instance to back up. Required only when `maintenance_oci_backup_run_backup` is `true`. |

All required variables are enforced by `ansible.builtin.assert` in `tasks/assert.ansible.yml`, which is itself gated behind `maintenance_oci_backup_enable` so a disabled role never demands credentials it won't use.

## Optional Variables

| Variable                                       | Default        | Description |
|-------------------------------------------------|----------------|-------------|
| `maintenance_oci_backup_enable`                  | `true`         | Master switch. When `false`, the role does nothing at all, including the required-variable assert. |
| `maintenance_oci_backup_run_backup`              | `true`         | Take a backup this run. |
| `maintenance_oci_backup_run_prune`               | `false`        | Prune old backups this run. Opt-in - deletion is never a silent side effect of taking a backup. |
| `maintenance_oci_backup_prune_dry_run`           | `true`         | Report what pruning would delete without deleting it. |
| `maintenance_oci_backup_name_prefix`             | `"maint"`      | Prefix for every object this role creates, so pruning can be scoped safely to only ever touch objects this role created. |
| `maintenance_oci_backup_type`                    | `"INCREMENTAL"`| Backup type passed to the OCI modules. |
| `maintenance_oci_backup_retention_days`          | `14`           | Backups older than this, whose name starts with `maintenance_oci_backup_name_prefix`, are eligible for pruning. Must be `> 0` (enforced by an assert in `tasks/prune.ansible.yml`). |
| `maintenance_oci_backup_include_block_volumes`   | `true`         | Also back up every block volume attached to the instance, not just the boot volume. Does **not** gate pruning: pruning always covers both boot and block backups already sitting in the compartment, so turning this off later doesn't silently stop cleanup of block backups created before it was. |
| `maintenance_oci_backup_wait`                    | `true`         | Wait for each backup to reach a terminal state before moving on. |
| `maintenance_oci_backup_wait_timeout`            | `1800`         | Seconds to wait when `maintenance_oci_backup_wait` is `true`. |

### Naming

Every object this role creates is named `maint-*` (or your `maintenance_oci_backup_name_prefix`) so pruning can be scoped safely:

- boot volume backup: `maint-<host_short>-boot-<YYYYMMDD>`
- block volume backup: `maint-<host_short>-block-<volume_display_name>-<YYYYMMDD>`

`<host_short>` is `inventory_hostname_short`. A single date-stamped name per volume per day is what makes the underlying modules' native idempotency (same input parameters -> no-op, no new resource) do the right thing on a same-day retry.

## Example Playbook

```yaml
- hosts: gafr_oci
  become: false
  gather_facts: true
  tasks:
    - name: Take an OCI backup of this instance
      ansible.builtin.include_role:
        name: guiand888.maintenance_oci_backup
      vars:
        maintenance_oci_backup_run_backup: true
        maintenance_oci_backup_instance_id: "{{ oci_instance_id }}"
        maintenance_oci_backup_compartment_id: "{{ oci_compartment_id }}"
        maintenance_oci_backup_tenancy: "{{ oci_tenancy }}"
        maintenance_oci_backup_region: "{{ oci_region }}"
        maintenance_oci_backup_api_user: "{{ oci_api_user }}"
        maintenance_oci_backup_api_user_fingerprint: "{{ oci_api_user_fingerprint }}"
        maintenance_oci_backup_api_user_key_content: "{{ oci_api_key_pem }}"

- hosts: gafr_oci
  become: false
  gather_facts: true
  tasks:
    - name: Prune this role's own backups older than the retention window (dry run)
      ansible.builtin.include_role:
        name: guiand888.maintenance_oci_backup
      vars:
        maintenance_oci_backup_run_backup: false
        maintenance_oci_backup_run_prune: true
        maintenance_oci_backup_prune_dry_run: true
        maintenance_oci_backup_compartment_id: "{{ oci_compartment_id }}"
        maintenance_oci_backup_tenancy: "{{ oci_tenancy }}"
        maintenance_oci_backup_region: "{{ oci_region }}"
        maintenance_oci_backup_api_user: "{{ oci_api_user }}"
        maintenance_oci_backup_api_user_fingerprint: "{{ oci_api_user_fingerprint }}"
        maintenance_oci_backup_api_user_key_content: "{{ oci_api_key_pem }}"
```

# Compatibility
Targets RHEL-family (EL 8/9, Fedora) and Debian-family (Debian bullseye/bookworm, Ubuntu focal/jammy/noble) managed hosts, though every OCI API call in this role runs `delegate_to: localhost` and never touches the managed host's OS directly - the platform list matters only in that it constrains where `inventory_hostname_short` and `gather_facts` (for `ansible_facts['date_time']`) are evaluated. Requires Ansible >= 2.12 and the `oracle.oci` collection (`requirements.yml`, pinned `>=5.5.0`) plus the `oci` Python SDK importable by the controller's Ansible interpreter. Syntax-check, `--check --diff`, and lint gates were run on a Fedora development host with `maintenance_oci_backup_enable: false`; not all listed platforms were exercised directly, and no test in this repo makes a real OCI API call.

# License
- AGPLv3

# Maintainers
Guillaume A.
  - Contact: [mail@guillaumea.fr](mailto:mail@guillaumea.fr)
  - Blog: https://blog.guillaumea.fr
