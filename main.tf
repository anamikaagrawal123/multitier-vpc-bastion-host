
# provider block required with Schematics to set VPC region
provider "ibm" {
  region = var.ibm_region
  #ibmcloud_api_key = var.ibmcloud_api_key
  generation = local.generation
  version    = "~> 1.4"
}

data "ibm_resource_group" "all_rg" {
  name = var.resource_group_name
}

locals {
  generation = 2
  blue_count = 1
  green_count  = 1
}


##################################################################################################
#  Select CIDRs allowed to access bastion host  
#  When running under Schematics allowed ingress CIDRs are set to only allow access from Schematics  
#  for use with Remote-exec and Redhat Ansible
#  When running under Terraform local execution ingress is set to 0.0.0.0/0
#  Access CIDRs are overridden if user_bastion_ingress_cidr is set to anything other than "0.0.0.0/0" 
##################################################################################################


data "external" "env" { program = ["jq", "-n", "env"] }
locals {
  region = lookup(data.external.env.result, "TF_VAR_SCHEMATICSLOCATION", "")
  geo    = substr(local.region, 0, 2)
  #schematics_ssh_access_map = {
  #  us = ["169.44.0.0/14", "169.60.0.0/14"],
  #  eu = ["158.175.0.0/16","158.176.0.0/15"],
  #}
  #schematics_ssh_access = lookup(["0.0.0.0/0"], local.geo, ["0.0.0.0/0"])
  #bastion_ingress_cidr  = var.ssh_source_cidr_override[0] != "0.0.0.0/0" ? var.ssh_source_cidr_override : local.schematics_ssh_access
  bastion_ingress_cidr  = ["0.0.0.0/0"]
}


module "vpc" {
  source               = "./vpc"
  ibm_region           = var.ibm_region
  resource_group_name  = var.resource_group_name
  generation           = local.generation
  unique_id            = var.vpc_name
  blue_count       = local.blue_count
  blue_cidr_blocks = local.blue_cidr_blocks
  green_count        = local.green_count
  green_cidr_blocks  = local.green_cidr_blocks
}

locals {
  # bastion_cidr_blocks  = [cidrsubnet(var.bastion_cidr, 4, 0), cidrsubnet(var.bastion_cidr, 4, 2), cidrsubnet(var.bastion_cidr, 4, 4)]
  blue_cidr_blocks = [cidrsubnet(var.blue_cidr, 4, 0), cidrsubnet(var.blue_cidr, 4, 2), cidrsubnet(var.blue_cidr, 4, 4)]
  green_cidr_blocks  = [cidrsubnet(var.green_cidr, 4, 0), cidrsubnet(var.green_cidr, 4, 2), cidrsubnet(var.green_cidr, 4, 4)]
}


# Create single zone bastion
module "bastion" {
  source                   = "./bastionmodule"
  ibm_region               = var.ibm_region
  bastion_count            = 1
  unique_id                = var.vpc_name
  ibm_is_vpc_id            = module.vpc.vpc_id
  ibm_is_image_id          = data.ibm_is_image.os.id
  ibm_is_resource_group_id = data.ibm_resource_group.all_rg.id
  bastion_cidr             = var.bastion_cidr
  ssh_source_cidr_blocks   = local.bastion_ingress_cidr
  destination_cidr_blocks  = [var.blue_cidr, var.green_cidr]
  destination_sgs          = [module.blue.security_group_id, module.green.security_group_id]
  # destination_sg          = [module.blue.security_group_id, module.green.security_group_id]
  # vsi_profile             = "cx2-2x4"
  # image_name              = "ibm-centos-8-3-minimal-amd64-3"
  ssh_key_id = data.ibm_is_ssh_key.sshkey.id

}


module "blue" {
  source                   = "./bluemodule"
  ibm_region               = var.ibm_region
  unique_id                = var.vpc_name
  ibm_is_vpc_id            = module.vpc.vpc_id
  ibm_is_resource_group_id = data.ibm_resource_group.all_rg.id
  blue_count           = local.blue_count
  profile                  = var.profile
  ibm_is_image_id          = data.ibm_is_image.os.id
  ibm_is_ssh_key_id        = data.ibm_is_ssh_key.sshkey.id
  subnet_ids               = module.vpc.blue_subnet_ids
  bastion_remote_sg_id     = module.bastion.security_group_id
  bastion_subnet_CIDR      = var.bastion_cidr
  pub_repo_egress_cidr     = local.pub_repo_egress_cidr
  app_blue_sg_id           = module.blue.security_group_id
}

module "green" {
  source                   = "./greenmodule"
  ibm_region               = var.ibm_region
  unique_id                = var.vpc_name
  ibm_is_vpc_id            = module.vpc.vpc_id
  ibm_is_resource_group_id = data.ibm_resource_group.all_rg.id
  green_count            = local.green_count
  profile                  = var.profile
  ibm_is_image_id          = data.ibm_is_image.os.id
  ibm_is_ssh_key_id        = data.ibm_is_ssh_key.sshkey.id
  subnet_ids               = module.vpc.green_subnet_ids
  bastion_remote_sg_id     = module.bastion.security_group_id
  bastion_subnet_CIDR      = var.bastion_cidr
  app_green_sg_id          = module.green.security_group_id
  pub_repo_egress_cidr     = local.pub_repo_egress_cidr
  vsi-blue-green-lb        = module.blue.lb_hostname
  vsi-blue-green-lb-id     = module.blue.lb_id
}
