terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.11"
    }
  }

  # 状態ファイルは infra/bootstrap/stg が作るバケットに置く。
  # バケットができる前の validate は `terraform init -backend=false`。
  backend "gcs" {
    bucket = "mouthy-stg-tfstate"
    prefix = "envs/stg"
  }
}

provider "google" {
  project = local.project_id
  region  = local.region
}
