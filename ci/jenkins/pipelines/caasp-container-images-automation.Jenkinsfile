// type of worker required by the job
def worker_type = 'dcassany-images-integration'
def branch_prefix = "images_pr_"
def updated_images = ""

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
        G_ORG ="davidcassany"
    }
    options {
        timeout(time: 3, unit: 'HOURS')
    }
    stages {
        stage('Code checkout') { steps {
            checkout([$class: 'GitSCM',
                branches: [[name: "*/${BRANCH_NAME}"]],
                extensions: [[$class: 'LocalBranch'],[$class: 'WipeWorkspace']],
                userRemoteConfigs: [[
                    refspec: '+refs/pull/*/head:refs/remotes/origin/PR-*',
                    credentialsId: 'github-token',
                    url: "https://github.com/${G_ORG}/caasp-container-images"
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
                sh(script: "${env.UTILS} submitMergedPRs ${prefix}")
                // TODO trigger Containers:CR -> Containers release job
            }}
        }

        stage('Check changes in repository'){
            when {
                expression { env.CHANGE_ID != null }
            }
            steps { script { try {
                sh(script: "${env.UTILS} sentStatuses pending 'Checking changes' 'check_changes'")
                branch = "images_pr_${env.CHANGE_ID}"
                project = "${env.BRANCH_PRJ}:${branch}"
                updated_images = sh(
                    script: "${env.UTILS} listUpdatedImages", returnStdout: true
                ).trim()
                sh(script: "${env.UTILS} checkVersionChange '${updated_images}'")
                sh(script: "${env.UTILS} sentStatuses success 'Check done' 'check_changes'")
            } catch (err) {
                echo err.getMessage()
                sh(script: "${env.UTILS} sentStatuses failure 'Check failed' 'check_changes'")
                error("Error: basic PR checks failed")
            }}}
        }

        stage('Create image subprojects in Branches'){
            when {
                expression { env.CHANGE_ID != null && "${updated_images}" != ""}
            }
            steps { script { try {
                sh(script: "${env.UTILS} sentStatuses pending 'Branching images' 'create_branches'")
                sh(script: "${env.UTILS} branchImages ${branch} '${updated_images}'")
                sh(script: "${env.UTILS} sentStatuses success 'Building images' 'create_branches'")
                sh(script: "${env.UTILS} waitForImagesBuild ${project} '${updated_images}'")
                sh(script: "${env.UTILS} sentStatuses success 'Images build succeeded' 'create_branches'")
            } catch (err) {
                echo err.getMessage()
                sh(script: "${env.UTILS} sentStatuses failure 'Build failed' 'create_branches'")
                error("Error: branches creation or images build failed in OBS")
            }}}
        }

        stage('Post build checks') {
            when {
                expression { env.CHANGE_ID != null && "${updated_images}" != ""}
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
