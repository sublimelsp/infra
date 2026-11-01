locals {
  members = yamldecode(file("${path.module}/members.yaml"))
  teams   = yamldecode(file("${path.module}/teams.yaml"))
  team_members = merge([
    for team, config in local.teams : {
      for username in config.members : "${team}/${username}" => { team = team, username = username }
    }
  ]...)
}

resource "github_team" "team" {
  for_each = local.teams

  name        = each.key
  description = each.value.description
  privacy     = "closed"
}

resource "github_team_membership" "member" {
  for_each = local.team_members

  team_id  = github_team.team[each.value.team].id
  username = each.value.username
  # GitHub always makes organization owners team maintainers.
  role = local.members[each.value.username] == "admin" ? "maintainer" : "member"

  depends_on = [github_membership.member]
}
