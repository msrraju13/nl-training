pipeline {
  agent none

  environment {
    docker_label="nlclidocker"
    nlw_host="nlweb.shared"
    api_url="http://${env.nlw_host}:8080"
    zone_id="${ZONE_ID}"
  }

  stages {
    stage ('Prep workspace') {
      agent any
      steps {
        cleanWs()
        script {
          sh "uname -a"
          env.host_ip = sh(script: "getent hosts ${env.nlw_host} | head -n1 | grep -oE '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])'", returnStdout: true)
        }
      }
    }
    stage ('Check/Build Docker Agent') {
      agent any
      steps {
        script {
          imgCount = sh(script: "docker images -a --filter='label=${env.docker_label}' --format='{{.ID}}' | wc -l", returnStdout: true).toInteger()
          if(imgCount < 1)
            docker.build("${env.docker_label}:latest", "--rm --label '${env.docker_label}' -f ./infra/JenkinsBuildAgent-docker.Dockerfile .")
        }
      }
    }
    stage('Attach Worker') {
      agent {
        docker {
          image "${env.docker_label}:latest"
          args "--add-host ${env.nlw_host}:${env.host_ip} -e HOME=${env.WORKSPACE} -u root --privileged -v /var/run/docker.sock:/var/run/docker.sock"
        }
      }
      stages {
        stage('NeoLoad login') {
          steps {
            sh 'neoload --version'
            withCredentials([string(credentialsId: 'NLW_TOKEN', variable: 'NLW_TOKEN')]) {
              sh "neoload login --url ${env.api_url} $NLW_TOKEN"
            }
          }
        }
        stage('Start docker load infra') {
          steps {
            script {
              echo "zone_id: " + env.zone_id
              if("${env.zone_id}".equals("null") env.zone_id = "default"
              echo "zone_id: " + env.zone_id
              if(env.zone_id.trim().length() < 1 || env.zone_id=="default") // dynamically pick a zone
                env.zone_id = sh(script: "neoload zones | jq '[.[]|select((.controllers|length<1) and (.loadgenerators|length<1) and (.type==\"STATIC\"))][0] | .id' -r", returnStdout: true)
            }

            sh "neoload test-settings --zone ${env.zone_id} --lgs 2 --scenario sanityScenario createoruse 'infra-harness'"
            sh "neoload docker --addhosts='nlweb.shared=${env.host_ip}' attach"
          }
        }
      }
    }
  }
}
