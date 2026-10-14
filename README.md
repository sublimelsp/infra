# sublimelsp-infra

Terraform configuration for the [sublimelsp](https://github.com/sublimelsp) GitHub organization. It manages organization members, repository settings, direct repository collaborators, GitHub Actions permissions and default branch rulesets.

Changes are made by editing the YAML files and opening a pull request. GitHub Actions posts the Terraform plan as a comment on the pull request (the plan summary, a table of changed resources and a compact diff; on every push, earlier plan comments are hidden as outdated) and applies it once merged to `main`.

## Files

| File | Purpose |
| --- | --- |
| `repos.yaml` | Repositories, their settings and direct collaborators. |
| `members.yaml` | Organization members and their role. |
| `schemas/*.schema.json` | JSON schemas for the YAML files, for validation and completions in editors that use `yaml-language-server`. |
| `repos.tf`, `members.tf` | Terraform resources generated from the YAML files. |
| `versions.tf` | Terraform and provider versions, HCP Terraform state and the GitHub provider. |
| `imports.tf` | One-time import of the existing GitHub Actions permissions. Delete after the first apply. |
| `.github/workflows/terraform.yml` | Plan on pull requests, apply on push to `main`. |
| `.github/scripts/plan-report.sh` | Builds the plan report used for the pull request comment and the workflow run summary. |

## Making changes

### Members

Edit `members.yaml`. The role is either `admin` (organization owner) or `member`. Adding a user sends an invitation; removing one removes them from the organization.

### Repositories

`repos.yaml` has a `defaults` section and a `repos` section. Each repository only lists the values that differ from `defaults`:

```yaml
repos:
  LSP-example:
    description: Example support for Sublime's LSP plugin
    homepage_url: https://example.com
    topics:
    - lsp
    - sublime-text
    has_wiki: false
    collaborators:
      some-user: maintain
```

Available keys:

| Key | Description |
| --- | --- |
| `description`, `homepage_url`, `topics` | Repository metadata. |
| `visibility` | `public` or `private`. |
| `has_issues`, `has_projects`, `has_wiki`, `has_discussions` | Enabled features. |
| `allow_merge_commit`, `allow_squash_merge`, `allow_rebase_merge` | Allowed pull request merge methods. |
| `allow_auto_merge`, `allow_update_branch`, `delete_branch_on_merge` | Pull request options. |
| `archived` | Archive the repository. Unarchiving is not supported by the GitHub API. |
| `collaborators` | Direct collaborators (`username: permission`). Permission is one of `pull`, `triage`, `push`, `maintain`, `admin`. Collaborators not listed here are removed. |
| `protect_default_branch` | Add the "default branch" ruleset, which blocks deleting and force pushing the default branch. Ignored for archived repositories. |
| `require_linear_history` | Also require linear history on the default branch. |
| `actions_enabled` | Enable GitHub Actions. Ignored for archived repositories. |
| `actions_allowed` | Actions that may run: `all`, or `local_only` (only actions and reusable workflows in the organization). |
| `ruleset_bypass_integrations` | GitHub App IDs that may bypass the default branch ruleset via pull requests. |
| `required_status_checks` | GitHub Actions check names that must pass before merging into the default branch. Adds the "Require CI" ruleset, which repository admins can bypass. |

To create a new repository, add an entry. Removing an entry **archives** the repository (`archive_on_destroy`); it is never deleted by Terraform.

Pages, security and analysis settings and the repository template are not managed and can be changed in the GitHub UI.

## Authentication

Terraform needs two tokens:

- **GitHub:** a token of an organization owner with the `admin:org` and `repo` scopes. The provider reads it from `GITHUB_TOKEN`, or falls back to the GitHub CLI token if `GITHUB_TOKEN` is not set. To use the GitHub CLI, make sure its token has the `admin:org` scope (check with `gh auth status`):

  ```bash
  gh auth refresh -h github.com -s admin:org
  ```

  Or export the token explicitly:

  ```bash
  export GITHUB_TOKEN="$(gh auth token)"
  ```

- **HCP Terraform** (stores the state): log in once with:

  ```bash
  terraform login
  ```

## Running locally

```bash
terraform init
```

```bash
terraform plan
```

Prefer applying through a pull request. If you need to apply locally, run `terraform apply` and read the plan carefully before confirming.

## Initial setup

These steps are needed only once.

1. In [HCP Terraform](https://app.terraform.io), create the organization `sublimelsp` (or change `organization` in `versions.tf`) and a CLI-driven workspace named `github-org`. In the workspace's settings, set **Execution Mode** to **Local**, so plans run in GitHub Actions or on your machine and HCP Terraform only stores the state.

2. In this repository's settings, add the Actions secrets:
   - `TF_API_TOKEN`: an HCP Terraform team or user API token with access to the workspace.
   - `ORG_ADMIN_TOKEN`: a GitHub token of an organization owner with the `admin:org` and `repo` scopes.

3. Import the existing organization into the state. `imports.tf` imports all repositories, collaborators, members and the existing default branch and "Require CI" rulesets. Review the plan, then apply it:

   ```bash
   terraform init
   ```

   ```bash
   terraform plan
   ```

   ```bash
   terraform apply
   ```

   At the time of writing, the plan imports everything without changing existing settings. Apart from that, it renames the 5 existing default branch rulesets to "default branch" and creates the same ruleset on the other 89 non-archived repositories. Set `protect_default_branch: false` in `defaults` before applying if you don't want that.

4. Delete `imports.tf` and commit. Otherwise adding a new repository fails, because Terraform tries to import it.

## Not managed

- The legacy branch protection rules on `LSP-biome`, `LSP-lua`, `LSP-marksman`, `LSP-terraform` and `LSP-yaml`. They still apply alongside the ruleset and can be deleted in the GitHub UI once the ruleset covers them.
- The disabled "st3 branch" ruleset on `LSP`.
- Organization-wide settings and teams (the organization has no teams). Organization rulesets require a paid GitHub plan, so the default branch ruleset is created per repository.
