terraform {
  required_version = ">= 1.7"

  # State is stored in HCP Terraform. The workspace uses the "Local" execution mode, so plan and apply run on the
  # machine that invokes them (your computer or GitHub Actions) and only the state lives in HCP Terraform.
  cloud {
    organization = "sublimelsp"

    workspaces {
      name = "github-org"
    }
  }

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}

# Authenticates with the GITHUB_TOKEN environment variable or, if not set, with the token of the GitHub CLI (`gh auth token`).
provider "github" {
  owner = "sublimelsp"
}
