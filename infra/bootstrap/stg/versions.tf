terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.11"
    }
  }

  # 初回はローカルの状態ファイルで apply する (バケットがまだ無いため)。
  # apply のあと、下を有効にして `terraform init -migrate-state` でバケットへ移す。
  # backend "gcs" {
  #   bucket = "mouthy-stg-tfstate"
  #   prefix = "bootstrap/stg"
  # }
}

provider "google" {
  project = local.project_id
  region  = local.region
}
