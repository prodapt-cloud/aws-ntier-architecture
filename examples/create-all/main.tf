# ---------------------------------------------------------------------------------------
#
# This a template file containing all resources within the modules and uses them to
# create the needed resources.
#
# ---------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------
#
# Terraform version should be used by this template
#
# ---------------------------------------------------------------------------------------
terraform {
  required_version = "0.12.10"
}

# ---------------------------------------------------------------------------------------
#
# The cloud provider configuration. In this case we are using AWS. The default region
# is 'us-east-1'. See https://docs.aws.amazon.com/general/latest/gr/rande.html for more
# regions.
#
# shared_credentials_file contains your access_key and secret_key provided by AWS. Usually
# it is stored on the path used below. Change it to the path where the credential is located
#
# ---------------------------------------------------------------------------------------

provider "aws" {
  region                  = "us-east-1"
  shared_credentials_file = "~/.aws/credentials"
}

# ---------------------------------------------------------------------------------------
#
# Key pairs uploaded in AWS and will be used by the instances for SSH connections
# Filename keypair that is located at the same directory with this
# template is used.
#
# ---------------------------------------------------------------------------------------

resource "aws_key_pair" "key-pair" {
  key_name   = "simple-key-pair"
  public_key = file("${path.cwd}/keypair")
}

# ---------------------------------------------------------------------------------------
#
# Simple template of VPC that'll be created for the project.
# Parameters:
#
# vpc-cidr-block      = CIDR block for the VPC. Default 10.0.0.0/16 (optional)
# project             = Project name of the VPC. Default simple-project (optional)
# public-subnet-cidr  = CIDR block for public subnets. Default ["10.0.1.0/24",
#                                                               "10.0.5.0/24",
#                                                               "10.0.10.0/24"] (optional)
#
# private-subnet-cidr = CIDR block for private subnets. Default ["10.0.21.0/24",
#                                                                "10.0.25.0/24",
#                                                                "10.0.30.0/24"] (optional)
#
# ---------------------------------------------------------------------------------------
module "project-vpc" {
  source = "../../modules/vpc"
}

# ---------------------------------------------------------------------------------------
#
# Security groups that is publicly and privately accessible.
# security-group-public open port 80 and 443 to 0.0.0.0/0.
# security-group-instances open port 80 to security-group-public.
#
# Parameters:
#
# name               = Name to be provided for the security group. Required
# description        = Description for the security group. (optional)
# vpc-id             = VPC where the security group is attached. Required
# ingress-ports      = List of ingress ports to be allowed in the public group. Default ["80"]
# allowed-cidr-block = List of CIDR block allowed on the security group. Default []
#                      Required if security-group-ids is [].
# security-group-ids = List of Security Group ids allowed on the security group. Default []
#                      Required if allowed-cidr-block is [].
#
# ---------------------------------------------------------------------------------------
module "security-group-public" {
  source = "../../modules/security-groups"

  name               = "simple-project-default"
  description        = "allow port 80"
  vpc-id             = module.project-vpc.vpc-id
  ingress-ports      = ["80", "443"]
  allowed-cidr-block = ["0.0.0.0/0"]
}

module "security-group-instance" {
  source = "../../modules/security-groups"

  name               = "simple-project-sg"
  description        = "allow port 80"
  vpc-id             = module.project-vpc.vpc-id
  ingress-ports      = ["80"]
  security-group-ids = [module.security-group-public.id]
}

# ---------------------------------------------------------------------------------------
#
# Instance cluster deployed in private subnet. It is also possible to create publicly
# accessible instances by changing the subnet and subnets being used by the instance.
# Instances created through this template has a t2.micro instance type.
#
# Parameters:
# subnet-ids         = List of subnets that is going to be use by the instance. Required
# project            = Project where the instance belong. Default simple-project. Optional
# key-pair           = Allowed public key pair name to be assigned on the instance. Required
# user-data          = User data in string to be executed upon initializing the instance. Optional
# desired-instance   = Desired instance to be deployed across the given subnets. Default 3
# security-group-ids = list of security group ids to be attached to the intances. Required
#
# ---------------------------------------------------------------------------------------
module "instance-cluster-private" {
  source = "../../modules/ec2"

  desired-instance   = 3
  project            = "simple-project"
  subnet-ids         = module.project-vpc.private-subnet-ids
  security-group-ids = [module.security-group-instance.id]
  key-pair           = aws_key_pair.key-pair.key_name
  user-data          = file("${path.cwd}/modules/install_nginx/install")
}

# ---------------------------------------------------------------------------------------
#
# Internet facing Application Load Balancer for the intances that is created in the private subnet.
# Routes port 443 to port 80 of the instances.
#
# Parameters:
# name            = Name for the ALB. Required
# instances-ids   = Instance ids to be attached on the load balancers target group. Required
# subnets         = Subnets where the load balancer is deployed. Required
# security-groups = List of security group for the load balancer. Required
# vpc-id          = VPC for the load balancer. Required
# certificate-arn = Certificate arn for the load balancer. Requried. 
#                   Note: ACM requires validated domain to issue SSL certificate.
#
# ---------------------------------------------------------------------------------------

module "application-load-balancer" {
  source = "../../modules/elb"

  name            = "simple-project-elb"
  instance-ids    = module.instance-cluster-private.ids
  subnets         = module.project-vpc.public-subnet-ids
  security-groups = [module.security-group-public.id]
  vpc-id          = module.project-vpc.vpc-id
  certificate-arn = module.https-connection.arn
}

# ---------------------------------------------------------------------------------------
# Adds subdomain record for the to connect on Application Load Balancer
#
# Parameters:
# subdomain        = Sub-domain A record to be created. Required
# hosted-zone-name = Hosted zone name for the subdomain. Required
# lb-dns           = DNS of the load balancers to be attached on the created A Record. Required
# lb-zone-id       = Hosted zone used by the load balancer. Required
# ---------------------------------------------------------------------------------------
module "subdomain-record" {
  source = "../../modules/domain-routes"

  subdomain        = var.sub-domain
  hosted-zone-name = var.hosted-zone-name
  lb-dns           = module.application-load-balancer.dns
  lb-zone-id       = module.application-load-balancer.zone-id
}

# ---------------------------------------------------------------------------------------
# Creates ACM Certificate for the subdomain and attached a listener to the 
# load balancer created.
#
# Parameters:
# 
# domain            = Domain name for the architecture. Required
# hosted-zone-name  = Hosted zone name for ACM Verification. Required
# alternative-names = Alternative domain names for the SSL Certificate
# elb-arn           = Load balancer arn where to attach the certificate
# target-group-arn  = Target group arn for the listener
# ---------------------------------------------------------------------------------------
module "https-connection" {
  source = "../../modules/acm-ssl"

  domain            = var.domain-name
  hosted-zone-name  = var.hosted-zone-name
  alternative-names = ["*.${var.domain-name}"]
}

