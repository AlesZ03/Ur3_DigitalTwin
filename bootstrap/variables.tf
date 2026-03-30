provider "aws" {
  region = "eu-central-1"
}

variable "github_repo" {
  description = "A GitHub repód neve (formátum: felhasznalonev/repo-nev)"
  type        = string
  default     = "AlesZ03/Ur3_DigitalTwin"
}