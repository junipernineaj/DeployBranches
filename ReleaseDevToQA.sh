#!/bin/bash


# Script to prepare a release to QA from DEV
# Inputs will be Release ID you want
#
# Relies on common.sh for commonly used functions

source ./common.sh

NameThatDatalakeETLVersion () {

until [ $DATALAKE_ETL_VERSION ]
do

echo "Which Glue Code version do you want to use?
"
read DATALAKE_ETL_VERSION
done

debugging "Datalake ETL Release Version (Bitbucket): $DATALAKE_RELEASE_VERSION"


}

NameThatStepFunctionVersion () {

until [ $DATALAKE_STEPFUNCTION_VERSION ]
do

echo "Which Step Function Code version do you want to use?
"
read DATALAKE_STEPFUNCTION_VERSION

done

debugging "Datalake Step Function Release Version (Bitbucket): $DATALAKE_STEPFUNCTION_VERSION"

}


CreateAWSCodeBucket () {

debugging "Running the CreateAWSCodeBucket function"
debugging "Create New Code Buckets"

aws s3 sync s3://$DEVCODEBUCKET/$DATALAKE_ETL_VERSION s3://$DEVCODEBUCKET/$RELEASENAME
aws s3 sync s3://$DEVCODEBUCKET/$DATALAKE_ETL_VERSION s3://$QACODEBUCKET/$RELEASENAME
aws s3 sync s3://$DEVCODEBUCKET/$DATALAKE_STEPFUNCTION_VERSION s3://$DEVCODEBUCKET/$RELEASENAME
aws s3 sync s3://$DEVCODEBUCKET/$DATALAKE_STEPFUNCTION_VERSION s3://$QACODEBUCKET/$RELEASENAME

debugging "Done."
}

SwitchToBranchFromMasterDevelopment () {

debugging "Switching Branch from Master"

case $DATASET in 

Other)
cat main.tf | sed s/ref=master/ref=$RELEASENAME/g > main.temp
mv main.temp main.tf
cat data_pipelines.tf | sed s/ref=master/ref=$RELEASENAME/g > data_pipelines.temp
mv data_pipelines.temp data_pipelines.tf
;;
Xeneta)
cat lambda.tf | sed s/ref=master/ref=$RELEASENAME/g > lambda.temp
mv lambda.temp lambda.tf
cat shared.tf | sed s/ref=master/ref=$RELEASENAME/g > shared.temp
mv shared.temp shared.tf
;;

esac

debugging "Done."

}

PushLocalBranchToRemoteDevelopment () {

debugging "Pushing branch $RELEASENAME in the remote Development Repository"

cd $REPOSITORY_PATH/$DEV_DIRECTORY
git add . | tee -a $LOGFILE
git commit -m "Release: $RELEASENAME preparation" | tee -a $LOGFILE
git push --set-upstream origin $RELEASENAME

debugging "Done."

}

##
## Checkout Repositories
##

CheckoutModules () {

debugging "Checking out Modules Repository"

cd $REPOSITORY_PATH
git clone $MODULES_REPOSITORY $MODULES_DIRECTORY

debugging "Done."

}

CheckoutDev () {

debugging "Checking out Development Repository"

cd $REPOSITORY_PATH
git clone $DEV_REPOSITORY $DEV_DIRECTORY

debugging "Done."

}

CheckoutQA () {

debugging "Checking out QA Repository"

cd $REPOSITORY_PATH
git clone $QA_REPOSITORY $QA_DIRECTORY

debugging "Done."

}

##
## Updates to files
##

UpdateGitLabCIymlForQA () {
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


UpdateVersionsAutoTFvarsForQA () {

debugging "Updating versions.auto.tfvars in QA Repository"

> versions.auto.tfvars

cat << EOF >> versions.auto.tfvars
datalake_version = "master"
datalakeetl_version = "$RELEASENAME"
trigger_version = "$RELEASENAME"
lambda_code_version = "$RELEASENAME"
EOF
}


UpdateTFVARSforQA () {
debugging "Updating terraform.tfvars in QA Repository"

cat terraform.tfvars | sed s/IcisDev/IcisQA/g > terraform.temp
cat terraform.temp | sed s/"isdev = 1"/"isdev = 0"/g > terraform.tfvars

if [ $DATASET = "Other" ]
then
cat << EOF >> terraform.tfvars
needs_tableau_server_role=1
trusted_tableau_server_aws_account="arn:aws:iam::512544833523:role/DataConsumerIcisQA-CHC-Assumed"
EOF
fi

rm terraform.temp

debugging "Done."
}

UpdatePlatformVersion () {
debugging "Updating Platform Version in Modules Repository"

awk '/trigger_version/{n=4}; n {n--; next}; 1' < modules/shared/output.tf > outfile
mv outfile modules/shared/output.tf
cat << EOF >> modules/shared/output.tf
output "trigger_version" {
  description = "Version of the platform - in AWS $DEVCODEBUCKET"
  value = "$RELEASENAME"
}
EOF

debugging "Done."
}

EnvironmentSpecificChangesForQA () {

debugging "Making Environment specific changes for QA"

UpdateTFVARSforQA
UpdateVersionsAutoTFvarsForQA
RemoveTerraformVersion
UpdateGitLabCIymlForQA

debugging "Done."

}


RemoveTerraformVersion () {
debugging "Removing default terraform version"

cat /dev/null > terraform_version.txt
}

RemoteAddDev () {
debugging "Remote adding Development to the QA Repository"

cd $REPOSITORY_PATH/$QA_DIRECTORY
git remote add $DEV_DIRECTORY $DEV_REPOSITORY

debugging "Done."

debugging "Fetching Metadata from the Remote Development Repository"
git fetch $DEV_DIRECTORY

debugging "Done."

}


##
## Other stuff
##

CheckoutRemoteBranchDev () {
debugging "Checking out the Remote Branch"

cd $REPOSITORY_PATH/$QA_DIRECTORY
git checkout $RELEASENAME

debugging "Done."

}


CommitChangesToBranchModulesLocal () {

debugging "Committing changes to the Release Branch for Modules Repository"

git add . | tee -a $LOGFILE
git commit -m "Release: $RELEASENAME taken on $DATETIMESTAMP" | tee -a $LOGFILE

debugging "Pushing the Release Branch to the Remote Repository"

git push --set-upstream origin $RELEASENAME

}

PushReleaseBranchToRemoteQA () {

debugging "Pushing Release Branch to Remote QA Repository"

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


CreateBranchModules () {

debugging "Creating local branch $RELEASENAME in the Modules Repository"

cd $REPOSITORY_PATH/$MODULES_DIRECTORY
git checkout -b $RELEASENAME

debugging "Done."

}

CreateBranchDev () {

debugging "Creating local branch $RELEASENAME in the Development Repository"

cd $REPOSITORY_PATH/$DEV_DIRECTORY
git checkout -b $RELEASENAME

SwitchToBranchFromMasterDevelopment
PushLocalBranchToRemoteDevelopment

debugging "Done."

}

## Clean Up Repositories

CleanupDev () {

debugging "Cleaning up Local Development Repository"

cd $REPOSITORY_PATH
rm -rf $DEV_DIRECTORY

debugging "Done."

}

CleanupQA () {

debugging "Cleaning up Local QA Repository"

cd $REPOSITORY_PATH
rm -rf $QA_DIRECTORY

debugging "Done."

}


CleanupModules () {

debugging "Cleaning up Modules Repository"

cd $REPOSITORY_PATH
rm -rf $MODULES_DIRECTORY

debugging "Done."

}



Main () {

CanIConnectToAWS
WhichDataset
NameThatRelease
HaveIUsedThisReleaseAlready
#
NameThatStepFunctionVersion
NameThatDatalakeETLVersion


#Create AWS Code Bucket

CreateAWSCodeBucket

#Take a cut of the Modules Repo

CheckoutModules
CreateBranchModules
UpdatePlatformVersion
CommitChangesToBranchModulesLocal
CleanupModules

#Create Release branch in the Main Dev Repo

CheckoutDev
CreateBranchDev

#Checkout QA Repo and fetch Dev Release branch in

CheckoutQA
RemoteAddDev
CheckoutRemoteBranchDev
EnvironmentSpecificChangesForQA
PushReleaseBranchToRemoteQA

#CleanUp after yourself

CleanupDev
CleanupQA
}

Main
