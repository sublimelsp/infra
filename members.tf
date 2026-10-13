resource "github_membership" "member" {
  for_each = yamldecode(file("${path.module}/members.yaml"))

  username = each.key
  role     = each.value
}
