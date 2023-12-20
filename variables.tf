variable "aws_access_key" {
  type = string
}

variable "aws_secret_key" {
  type = string
}

variable "aws_token" {
  type = string
}

variable "ec2_key_name" {
    type = string
    description = "Name of the EC2 key value pair. Do not add the extension."
}

variable "aws_account_id" {
  type = string
}

variable "aws_role_name" {
  type = string
  default = "LabRole"
}

variable "private_key_path" {
  type = string
}
