// type of worker required by the job
def worker_type = 'dcassany-images-integration'
def branch_prefix = "images_pr_"

pipeline {
   agent { node { label "${worker_type}" } }

    environment {
        GITHUB_TOKEN = credentials('github-token')
        IBS = credentials('ibs-user')
        GITHUB_ACCESS = credentials('images-token')
        UTILS = "ci/jenkins/pipelines/helpers/images-utils.sh"
        BASE_PRJ = "home:dcassany"
        SRC_PRJ = "${env.BASE_PRJ}:CR"
        BRANCH_PRJ = "${env.BASE_PRJ}:Branches"
    }
    options {
        timeout(time: 3, unit: 'HOURS') 
    }
    stages {
        stage('Prepare environment') { steps {
            checkout([$class: 'GitSCM',
                branches: [[name: "*/${BRANCH_NAME}"]],
                extensions: [[$class: 'LocalBranch'],[$class: 'WipeWorkspace']],
                userRemoteConfigs: [[
                    refspec: '+refs/pull/*/head:refs/remotes/origin/PR-*',
                    credentialsId: 'github-token',
                    url: 'https://github.com/davidcassany/caasp-container-images'
                ]]
            ])
        }}

        stage('Show variables') { steps {
            echo sh(script: 'env|sort', returnStdout: true)
        }}

        stage('Update merged PRs') {
            when {
                expression { env.BRANCH_NAME == 'master' && env.CHANGE_ID == null }
            }
            steps { script {
                prefix = "${env.BRANCH_PRJ}:${branch_prefix}"
                echo "${env.UTILS} submitMergedPRs ${prefix}"

                //sh(script: "${env.UTILS} submitMergedPRs ${prefix}")
                // TODO trigger Containers:CR -> Containers release job
            }}
        }

        stage('Create image subprojects in Branches'){
            when {
                expression { env.CHANGE_ID != null }
            }
            steps { script {
                sh(script: "${env.UTILS} sentStatuses pending 'Checking changes'")
                branch = "images_pr_${env.CHANGE_ID}"
                project = "${env.BRANCH_PRJ}:${branch}" 
                updated_images = sh(
                    script: "${env.UTILS} listUpdatedImages", returnStdout: true
                ).trim()
                sh(script: "${env.UTILS} checkVersionChange '${updated_images}'")
                sh(script: "${env.UTILS} sentStatuses pending 'Branching images'")
                sh(script: "${env.UTILS} branchImages ${branch} '${updated_images}'")
                sh(script: "${env.UTILS} sentStatuses pending 'Building images'") 
                sh(script: "${env.UTILS} waitForImagesBuild ${project} '${updated_images}'")
                sh(script: "${env.UTILS} sentStatuses success 'Images build succeeded'")
            }}
        }

        stage('Run tests') {
            when {
                expression { env.CHANGE_ID != null }
            }
            steps { script {
                echo "to be completed. Branched images '${updated_images}'"
                // #1 pull images
                // #2 Run trivy
                // #3 Apply drop-in tests concept
                // #4 clear pulled images
                // TODO update github status tests done
            }}
        }
    }
    post {
        //always {
        //   // TODO archive test results if any
        //}
        cleanup {
            dir("${WORKSPACE}") {
                deleteDir()
            }
        }
    }
}
