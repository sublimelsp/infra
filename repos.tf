locals {
  repos_config = yamldecode(file("${path.module}/repos.yaml"))

  repos = {
    for name, repo in local.repos_config.repos : name => merge(local.repos_config.defaults, repo)
  }
}

resource "github_repository" "repo" {
  for_each = local.repos

  name                   = each.key
  description            = try(each.value.description, null)
  homepage_url           = try(each.value.homepage_url, null)
  topics                 = try(each.value.topics, [])
  visibility             = each.value.visibility
  has_issues             = each.value.has_issues
  has_projects           = each.value.has_projects
  has_wiki               = each.value.has_wiki
  has_discussions        = each.value.has_discussions
  allow_merge_commit     = each.value.allow_merge_commit
  allow_squash_merge     = each.value.allow_squash_merge
  allow_rebase_merge     = each.value.allow_rebase_merge
  allow_auto_merge       = each.value.allow_auto_merge
  allow_update_branch    = each.value.allow_update_branch
  delete_branch_on_merge = each.value.delete_branch_on_merge
  archived               = each.value.archived

  # Removing a repository from repos.yaml archives it instead of deleting it.
  archive_on_destroy = true

  lifecycle {
    # Managed outside of Terraform.
    ignore_changes = [pages, security_and_analysis, template]
  }
}

# Direct (non-team) collaborators. Authoritative: collaborators not listed in repos.yaml are removed.
resource "github_repository_collaborators" "collaborators" {
  for_each = local.repos

  repository = github_repository.repo[each.key].name

  dynamic "user" {
    for_each = try(each.value.collaborators, {})
    content {
      username   = user.key
      permission = user.value
    }
  }
}

# Prevents deleting and force-pushing the default branch.
resource "github_repository_ruleset" "default_branch" {
  for_each = { for name, repo in local.repos : name => repo if repo.protect_default_branch && !repo.archived }

  name        = "default branch"
  repository  = github_repository.repo[each.key].name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = each.value.require_linear_history
  }

  dynamic "bypass_actors" {
    for_each = try(each.value.ruleset_bypass_integrations, [])
    content {
      actor_id    = bypass_actors.value
      actor_type  = "Integration"
      bypass_mode = "pull_request"
    }
  }
}

# Requires the listed GitHub Actions checks to pass before merging into the default branch. Repository admins can bypass it.
resource "github_repository_ruleset" "require_ci" {
  for_each = { for name, repo in local.repos : name => repo if length(try(repo.required_status_checks, [])) > 0 && !repo.archived }

  name        = "Require CI"
  repository  = github_repository.repo[each.key].name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = each.value.required_status_checks
        content {
          context        = required_check.value
          integration_id = 15368 # GitHub Actions
        }
      }
    }
  }

  bypass_actors {
    actor_id    = 5 # Repository admin role
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }
}
