
# Create a zip archive with the cloud function's source code
data "archive_file" "cloud_function_source_zip" {
  type        = "zip"
  source_dir  = var.source_path
  excludes    = [".git"]
  output_path = "${path.module}/watchdog_cloud_function_source.zip"
}

# Create a storage bucket for the cloud function's source code
resource "google_storage_bucket" "cloud_function_source_bucket" {
  name = var.source_bucket_name
  location = var.source_bucket_location
}

# Upload the cloud function's source code to the storage bucket
resource "google_storage_bucket_object" "cloud_function_bucket_object" {
  name   = format("%s#%s", "watchdog_cloud_function_source.zip", data.archive_file.cloud_function_source_zip.output_md5)
  bucket = google_storage_bucket.cloud_function_source_bucket.name
  source = "${path.module}/watchdog_cloud_function_source.zip"
}

# Deploy the cloud function
resource "google_cloudfunctions_function" "function" {
  name        = var.function_name
  description = "Watchdog"
  runtime     = "go113"
  region      = var.function_region

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.cloud_function_source_bucket.name
  source_archive_object = google_storage_bucket_object.cloud_function_bucket_object.name
  trigger_http          = true
  entry_point           = "RunWatchdog"
  environment_variables = {
    # No need to set GCP_PROJECT; it is reserved, and automatically set to the function's own project ID
    GCE_ZONE = var.build_agent_zone
    GITHUB_PAT = var.github_pat
    GITHUB_ORGANIZATION = var.github_organization
    GITHUB_REPOSITORY = var.github_repository
  }
}

# Create an IAM entry for invoking the function
# This IAM entry allows anyone to invoke the function via HTTP, without being authenticated
#
# It would be ideal to have the function require authentication, but that will be for later
#
# The two main risks posed by allowing this to be called unauthenticated are:
# - An external party could make the function reach the throttling limit for GitHub API calls
#   which will then result in no on-demand build agents being started/stopped for the remainder
#   of the hour. This, in turn, will delay builds and sometimes cost a bit extra money. (VMs
#   being active for up to 60 minutes more than necessary.)
# - An external party could see names of internal resources: VM names, names of GitHub repositories, and the like.
#   There is however no risk that actual game files, or secrets/keys get exposed.
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}
