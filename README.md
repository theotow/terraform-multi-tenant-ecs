# Terraform multi tenant ecs

This is a basic setup of an ecs cluster with one task definition to run an multi tenant webapp on.

## Run the setup
1. fill in the blanks
2. make sure you create the zone for your domain already in route53
2. ```terraform init```
3. ```terraform apply -var-file=./variables.json -auto-approve```

## Destroy setup

```terraform destroy -var-file=./variables.json -auto-approve```