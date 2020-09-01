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

This is a release candidate for Staging - taken on $DATETIMESTAMP.

A NEW code release bucket has been created which is shared across the uppers (Staging and Production)

We must create the following bucket manually - before we sync new code to it:

aws s3 mkdir s3://com.icis.datalake.releases.uppers
 
Once created we must ensure that the following buckets are synchronised:

# aws s3 sync s3://com.icis.datalake.releases.lowers  s3://com.icis.datalake.releases.uppers

*NB.* There is no account to do this at the moment so:

- 1. Copy the code.staging.icisdev folder named $RELEASENAME from the Dev AWS account to your machine
- 2. Push the folder called $RELEASENAME to code.staging.icisstaging
- 3. Run the Terraform Plan/Apply

EOF

debugging "Done."

}

##
## Checkout Repositories
##

CheckoutStaging () {

debugging "Checking out Staging Repository"

cd $REPOSITORY_PATH
git clone $STAGING_REPOSITORY $STAGING_DIRECTORY

debugging "Done."

}

##
## Updates to files
##

UpdateTFVARSforStaging () {
debugging "Updating terraform.tfvars in Staging Repository"

cat terraform.tfvars | grep -v tableau_server > terraform.temp
cat terraform.temp | sed s/IcisQA/IcisStg/g > terraform.temp2
cat terraform.temp2 | sed s/"isLowerEnv = 1"/"isLowerEnv = 0"/g > terraform.temp3
cat terraform.temp3 | sed s/"isUpperEnv = 0"/"isUpperEnv = 1"/g > terraform.tfvars

rm terraform.temp*

debugging "Done."
}

UpdateGitLabCIymlForStaging () {
debugging "Updating gitlab-ci.yml in Staging Repository"

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

EnvironmentSpecificChangesForStaging () {

debugging "Making Environment specific changes for Staging"

UpdateTFVARSforStaging
UpdateGitLabCIymlForStaging

debugging "Done."

}


RemoteAddQA () {
debugging "Remote adding QA to the Staging Repository"

cd $REPOSITORY_PATH/$STAGING_DIRECTORY
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

cd $REPOSITORY_PATH/$STAGING_DIRECTORY
git checkout $RELEASENAME

debugging "Done."

}


PushReleaseBranchToRemoteStaging () {

debugging "Pushing Release Branch to Remote Staging Repository"

git add . | tee -a $LOGFILE
git commit -m "Release: $RELEASENAME taken on $DATETIMESTAMP" | tee -a $LOGFILE
git push -u origin head

}


CheckoutRemoteBranchDev () {
debugging "Checking out the Remote Branch"

cd $REPOSITORY_PATH/$QA_DIRECTORY
git checkout $RELEASENAME

debugging "Done."

}


## Clean Up Repositories

CleanupStaging () {

debugging "Cleaning up Local Staging Repository"

cd $REPOSITORY_PATH
rm -rf $STAGING_DIRECTORY

debugging "Done."

}

Main () {

#NameThatRelease

#Checkout Staging Repository and Remote Add QA

CheckoutStaging
RemoteAddQA
CheckoutRemoteBranchQA
EnvironmentSpecificChangesForStaging
AddReleaseNotesForAWSCodeBucket
PushReleaseBranchToRemoteStaging
#

#CleanUp after yourself

#CleanupStaging
}

Main
