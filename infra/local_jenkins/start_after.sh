#!/bin/bash
set -e

source "`dirname $0`"/common.sh
source "`dirname $0`"/require_jenkins_secret.sh

echo 'Applying initial configurations to Jenkins container'

INSIDE_JENKINS_HOME=/var/jenkins_home
PIPELINE_TEMPLATE_FILE=pipeline.job.template.xml
git_repo_url=https://github.com/paulsbruce/neoload-ci-training.git
git_branch=master

docker cp "`dirname $0`"/$PIPELINE_TEMPLATE_FILE jenkins-blueocean:$INSIDE_JENKINS_HOME/$PIPELINE_TEMPLATE_FILE

function mkf_copy() {
  contents=$(echo "$1")
  filename=$2
  inside_path=$3
  inside_full_path=$INSIDE_JENKINS_HOME/$filename

  echo "${contents}" > ~/tmp.$filename
  docker cp ~/tmp.$filename jenkins-blueocean:$inside_full_path
  $(chown_j "$inside_full_path")
  rm ~/tmp.$filename
  echo $inside_full_path
}
function chown_j() {
  full_path=$1
  docker exec -it --user root jenkins-blueocean chown jenkins:jenkins $full_path
}
function chmod_x() {
  full_path=$1
  $(chown_j "$full_path")
  docker exec -it --user root jenkins-blueocean chmod +x $full_path
}
function uuid() {
  echo $(docker exec -it --user root jenkins-blueocean cat /proc/sys/kernel/random/uuid)
}

credential_xml="<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl plugin=\"plain-credentials@1.7\">
  <scope>GLOBAL</scope>
  <id>NLW_TOKEN</id>
  <description></description>
  <secret>$NLW_TOKEN</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>"
credential_xml=$(echo $credential_xml | tr -d '\r' | tr -d '\n')
credential_xml_fp=$(mkf_copy "$credential_xml" 'jenkins.nlw.xml')

rdc_xml="<?xml version='1.1' encoding='UTF-8'?>
<jenkins.security.ResourceDomainConfiguration>
 <url>$STATIC_JENKINS_URL</url>
</jenkins.security.ResourceDomainConfiguration>"
rdc_xml_fp=$(mkf_copy "$rdc_xml" 'jenkins.security.ResourceDomainConfiguration.xml')

shared_libs_xml="<?xml version='1.1' encoding='UTF-8'?>
<org.jenkinsci.plugins.workflow.libs.GlobalLibraries plugin=\"workflow-cps-global-lib@2.17\">
  <libraries>
    <org.jenkinsci.plugins.workflow.libs.LibraryConfiguration>
      <name>neoload-shared</name>
      <retriever class=\"org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever\">
        <scm class=\"jenkins.plugins.git.GitSCMSource\" plugin=\"git@4.4.4\">
          <id>$(uuid)</id>
          <remote>$git_repo_url</remote>
          <credentialsId></credentialsId>
          <traits>
            <jenkins.plugins.git.traits.BranchDiscoveryTrait/>
          </traits>
        </scm>
      </retriever>
      <defaultVersion>$git_branch</defaultVersion>
      <implicit>false</implicit>
      <allowVersionOverride>true</allowVersionOverride>
      <includeInChangesets>true</includeInChangesets>
    </org.jenkinsci.plugins.workflow.libs.LibraryConfiguration>
  </libraries>
</org.jenkinsci.plugins.workflow.libs.GlobalLibraries>"
shared_libs_xml_fp=$(mkf_copy "$shared_libs_xml" 'org.jenkinsci.plugins.workflow.libs.GlobalLibraries.xml')

docker cp "`dirname $0`"/hosts.add.sh jenkins-blueocean:$INSIDE_JENKINS_HOME/hosts.add.sh
chmod_x "$INSIDE_JENKINS_HOME/hosts.add.sh"
docker exec -it --user root jenkins-blueocean $INSIDE_JENKINS_HOME/hosts.add.sh

cli_prep="
set -e

export JENKINS_URL=$INT_JENKINS_URL JENKINS_USER_ID=$JENKINS_USER_ID JENKINS_API_TOKEN=$JENKINS_SECRET

curl -s -L $INT_JENKINS_URL/jnlpJars/jenkins-cli.jar -o /var/jenkins_home/jenkins-cli.jar
function jcli() {
  java -jar /var/jenkins_home/jenkins-cli.jar \"\$@\"
}

function cp_pipeline_job() {
  job_name=\$1
  file_name=\$2
  git_jenkinsfile_path=\$3
  echo \"Checking job \$job_name\"
  cp $INSIDE_JENKINS_HOME/$PIPELINE_TEMPLATE_FILE $INSIDE_JENKINS_HOME/\$file_name
  sed -i \"s|{{git_repo_url}}|$git_repo_url|g\" $INSIDE_JENKINS_HOME/\$file_name
  sed -i \"s|{{git_branch}}|$git_branch|g\" $INSIDE_JENKINS_HOME/\$file_name
  sed -i \"s|{{git_jenkinsfile_path}}|\$git_jenkinsfile_path|g\" $INSIDE_JENKINS_HOME/\$file_name
  if jcli get-job \"\$job_name\" > /dev/null 2>&1 ; then
    echo \"Job '\$job_name' already exists; not overwriting\"
  else
    cat $INSIDE_JENKINS_HOME/\$file_name | jcli create-job \"\$job_name\"
    echo \"Created job '\$job_name'\"
  fi
}
"
cli_prep_fp=$(mkf_copy "$cli_prep" 'jenkins.cli.prep.sh')
chmod_x $cli_prep_fp

contents_config="
#!/bin/sh

source $cli_prep_fp

jcli install-plugin ws-cleanup basic-branch-build-strategies build-user-vars-plugin pipeline-stage-view test-results-analyzer groovy-postbuild
# list-credentials system::system::jenkins

set +e
echo 'Applying NLW secret to credential store'
cat $credential_xml_fp | jcli create-credentials-by-xml system::system::jenkins \"(global)\"
set -e

echo \$(cp_pipeline_job 'Start Infra' 'start_infra.xml' 'infra/start_infra.Jenkinsfile')
echo \$(cp_pipeline_job 'Stop Infra' 'stop_infra.xml' 'infra/stop_infra.Jenkinsfile')
echo \$(cp_pipeline_job 'Rebuild CLI Agent' 'rebuild_agent.xml' 'infra/rebuildAgent.Jenkinsfile')

echo \$(cp_pipeline_job 'module1' 'module_1.xml' 'modules/module1/Jenkinsfile')
echo \$(cp_pipeline_job 'moduleX' 'module_X.xml' 'modules/moduleX/Jenkinsfile')

sleep 10
jcli build 'Rebuild CLI Agent' -s

#echo 'Restarting Jenkins after applying initial configurations'
#jcli safe-restart
sleep 5
"
contents_config_fp=$(mkf_copy "$contents_config" 'jenkins.config.sh')
chmod_x $contents_config_fp
docker exec -it jenkins-blueocean sh $contents_config_fp

echo "Jenkins secret: $JENKINS_SECRET"

source "`dirname $0`"/wait_for_jenkins_up.sh
