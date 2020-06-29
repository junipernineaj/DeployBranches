#!/bin/bash


# Script to prepare a release to Staging from QA
# Inputs will be Release ID you want

# Variables

DEBUG="On"
OIFS="$IFS"
IFS=$'\n'
LOGDATETIMESTAMP=`date "+%Y%m%d-%H%M%S"`

REPOSITORY_PATH=$PWD
LOGFILE=$REPOSITORY_PATH/logs/$LOGDATETIMESTAMP-Release.txt

MODULES_REPOSITORY="git@cipipeline.rbxd.ds:MODULES/CH/datalake.git"
DEV_REPOSITORY="git@cipipeline.rbxd.ds:AWS-CHC/CHC-RESGRP-DataLake-Dev-EW.git"
QA_REPOSITORY="git@cipipeline.rbxd.ds:AWS-CHC/chc-resgrp-datalake-qa-ew.git"
STAGING_REPOSITORY="git@cipipeline.rbxd.ds:AWS-CHS/chs-datalake-staging-ew.git"
PRODUCTION_REPOSITORY="git@cipipeline.rbxd.ds:AWS-CHS/chs-datalake-prod-ew.git"
SANDBOX_REPOSITORY="git@cipipeline.rbxd.ds:AWS-CHC/test-chc-resgrp-datalake-dev-ew.git"

MODULES_DIRECTORY="Modules"
DEV_DIRECTORY="Development"
QA_DIRECTORY="QA"
STAGING_DIRECTORY="Staging"
PRODUCTION_DIRECTORY="Production"
SANDBOX_DIRECTORY="Sandbox"

mkdir $REPOSITORY_PATH/logs

RELEASENAME=$1

logging () {

DATETIMESTAMP=`date "+%Y%m%d-%H%M%S"`
MESSAGE=$1
echo $DATETIMESTAMP - "$MESSAGE" >> $LOGFILE
}

debugging () {

DATETIMESTAMP=`date "+%Y%m%d-%H%M%S"`
MESSAGE=$1

if [ $DEBUG == "On" ]
then
        echo $DATETIMESTAMP - "$MESSAGE" | tee -a $LOGFILE
fi
}


NameThatRelease () {

echo "What release name do you want to use?
"
read RELEASENAME

debugging "Creating Release: $RELEASENAME"

}


AddReleaseNotesForAWSCodeBucket () {

debugging "Adding Release notes for AWS Code Bucket changes"

> README.md
cat << EOF >> README.md
# Release $RELEASENAME 

## Datalake-core

This is a release candidate for Production - taken on $DATETIMESTAMP.

We must ensure that the following buckets are synchronised:

```
# aws s3 sync s3://code.staging.icisdev/$RELEASENAME  s3://code.staging.icisprod
```

*NB.* There is no account to do this at the moment so:

- 1. Copy the code.staging.icisdev folder named $RELEASENAME from the Dev AWS account to your machine
- 2. Push the folder called $RELEASENAME to code.staging.icisprod
- 3. Run the Terraform Plan/Apply

EOF

debugging "Done."

}

##
## Checkout Repositories
##

CheckoutProduction () {

debugging "Checking out Production Repository"

cd $REPOSITORY_PATH
git clone $PRODUCTION_REPOSITORY $PRODUCTION_DIRECTORY

debugging "Done."

}

##
## Updates to files
##

UpdateTFVARSforProduction () {
debugging "Updating terraform.tfvars in Staging Repository"

cat terraform.tfvars | grep -v tableau_server > terraform.temp
cat terraform.temp | sed s/IcisQA/IcisProd/g > terraform.temp2
cat terraform.temp2 | sed s/"isLowerEnv = 1"/"isLowerEnv = 0"/g > terraform.tfvars
echo "tdm_historical_incremental_etl_lambda_schedule_enabled = true" >> terraform.tfvars

rm terraform.temp*

debugging "Done."
}


UpdateProviderTFforProduction () {
debugging "Updating gitlab-ci.yml in Production Repository"

>> provider.tf
cat << EOF > provider.tf
variable "aws_region" {}

provider "aws" {
  region = "\${var.aws_region}"
}

EOF
}



UpdateGitLabCIymlForProduction () {
debugging "Updating gitlab-ci.yml in Production Repository"

cat << EOF > .gitlab-ci.yml
variables:
  ## runner terraform-ci scripts
  MASTER_SCRIPTS: "\${RUNNER_BASEDIR}/repos/terraform-ci-scripts"

  ## runner terraform-ci config
  MASTER_CONFIG:  "\${RUNNER_BASEDIR}/repos/terraform-ci-config"

  ## path to the project in GitLab
  TF_VAR_project_path: \$CI_PROJECT_PATH


stages:
  - verify
  - plan
  - apply

before_script:
  - . \$MASTER_SCRIPTS/pre-stage.sh

after_script:
  - . \$MASTER_SCRIPTS/post-stage.sh

VERIFY-State:
  stage: verify
  script:
    - . \$MASTER_SCRIPTS/stage-1_verify_saved_state.sh
  except:
    - state
  tags:
    - aws
  allow_failure: true

TERRAFORM-Plan:
  stage: plan
  script:
    - . \$MASTER_SCRIPTS/stage-2_terraform_plan.sh
  except:
    - state
  tags:
    - aws
  when: on_success
  allow_failure: false

TERRAFORM-Apply:
  stage: apply
  script:
    - . \$MASTER_SCRIPTS/stage-3_terraform_apply.sh
  except:
    - state
  only:
    - master
  tags:
    - aws
  when: manual
  allow_failure: false

EOF

debugging "Done."

}

EnvironmentSpecificChangesForProduction () {

debugging "Making Environment specific changes for Production"

UpdateTFVARSforProduction
UpdateGitLabCIymlForProduction
##UpdateProviderTFforProduction

debugging "Done."

}


RemoteAddQA () {
debugging "Remote adding QA to the Production Repository"

cd $REPOSITORY_PATH/$PRODUCTION_DIRECTORY
git remote add $QA_DIRECTORY $QA_REPOSITORY

debugging "Done."

debugging "Fetching Metadata from the Remote QA Repository"
git fetch $QA_DIRECTORY

debugging "Done."

}


##
## Other stuff
##

CheckoutRemoteBranchQA () {
debugging "Checking out the Remote QA Branch"

cd $REPOSITORY_PATH/$PRODUCTION_DIRECTORY
git checkout $RELEASENAME

debugging "Done."

}


PushReleaseBranchToRemoteProduction () {

debugging "Pushing Release Branch to Remote Production Repository"

git add . | tee -a $LOGFILE
git commit -m "Release: $RELEASENAME taken on $DATETIMESTAMP" | tee -a $LOGFILE
git push -u origin head

}


## Clean Up Repositories

CleanupProduction () {

debugging "Cleaning up Local Production Repository"

cd $REPOSITORY_PATH
rm -rf $PRODUCTION_DIRECTORY

debugging "Done."

}

Main () {

NameThatRelease

#Checkout Staging Repository and Remote Add QA

CheckoutProduction
RemoteAddQA
CheckoutRemoteBranchQA
EnvironmentSpecificChangesForProduction
AddReleaseNotesForAWSCodeBucket
PushReleaseBranchToRemoteProduction
#

#CleanUp after yourself

CleanupProduction
}

Main
