set -e

if [ -z "${IMAGE_NAME}" ]; then
  echo "Missing required ENV variables; Exiting." && exit 1
fi

# Script Variables / Defaults
EXTRA_BUILD_ARGS=${EXTRA_BUILD_ARGS:-""}
DOCKERFILE_DIRECTORY=${DOCKERFILE_DIRECTORY:-"./"}
DOCKERFILE_NAME=${DOCKERFILE_NAME:-"Dockerfile"}
ARTIFACT_PATHS=${ARTIFACT_PATHS:-"/test-results"}
CACHED_TARGETS=${CACHED_TARGETS:-"tooling,dependencies"}
PULL_IMAGES=${PULL_IMAGES:-""}
CACHE_LAYER_PREFIX=${CACHE_LAYER_PREFIX:-$IMAGE_NAME}
RELEASE_TARGET=${RELEASE_TARGET:-$IMAGE_NAME}
SEMVER=${SEMVER:-1.0.0}
dockerfile_directory=${DOCKERFILE_DIRECTORY:-./}
dockerfile_name=${DOCKERFILE_NAME:-Dockerfile}
DOCKERFILE="${dockerfile_directory%/}/${dockerfile_name}"
CACHED_TARGETS=${CACHED_TARGETS:-tooling,dependencies,runtime}
GIT_BRANCH=${GITHUB_REF}
GIT_SHA_SHORT=$(git rev-parse --short HEAD)
LOCAL_IMAGE_TAG="${IMAGE_NAME}:${SEMVER}_${GIT_SHA_SHORT}"
echo "Dockerfile: ${DOCKERFILE}"
echo "GIT_BRANCH: ${GIT_BRANCH}"
echo "Git commit hash: ${GIT_SHA_SHORT}"
echo "Targets to cache: ${CACHED_TARGETS}"
echo "build_args: ${build_args}"
echo "semver: ${SEMVER}"
# Validate SEMVER
semver diff ${SEMVER} ${SEMVER}
# Save ENV variables for downstream Github Action steps
echo "GIT_SHA_SHORT=${GIT_SHA_SHORT}" >> $GITHUB_ENV
echo "ESCAPEDSEMVER=${SEMVER//[-+]/_}" >> $GITHUB_ENV
echo "LOCAL_IMAGE_TAG=${LOCAL_IMAGE_TAG}" >> $GITHUB_ENV

build_target() {
  _target=${1}
  _tag=${2}
  command="DOCKER_BUILDKIT=1 docker build --pull "
  command+="--target \"${_target}\" "
  if [ ! -z "${_tag}" ]; then
    # Final build stage only
    echo "Final build target: ${_target}"
    command+="-t \"${_tag}\" "
    command+="--squash "
  elif [[ $CACHED_TARGETS == *"${_target}"* ]]; then
    echo "Caching target: ${_target}"
    command+="-t \"${CACHE_LAYER_PREFIX}_${_target}\" "
  elif [[ "$_target" == *"report"* ]]; then
    echo "Extracting test results to ./build"
    command+="--output ./build "
  fi
  command+="--build-arg SEMVER=\"${SEMVER}\" ${EXTRA_BUILD_ARGS} "
  command+="-f ${DOCKERFILE} ./ "
  echo $command
  eval $command
}


###############
# Warmup
###############

for _ in {1..12}; do
  [[ "$(ps aux | grep -c '[d]ocker system prune\|[d]ocker rmi')" -ne "0" ]] && echo "waiting for docker image cleanup to finish before starting the build" && sleep 10
done

# Refresh Images
echo "Pulling latest images..."
for image in ${PULL_IMAGES//,/ }; do
    docker pull "${image}"
done

###############
# Build
###############


stages=($(cat ${DOCKERFILE} | grep -o 'as [a-z-]*' | sed 's/as //'));
for stage in ${stages[@]}; do
  if [[ $stage == "${RELEASE_TARGET}" ]]; then
    continue
  fi
  echo "Building Stage: '${stage}'"
  build_target ${stage}
done

# Build Final Target
build_target ${RELEASE_TARGET} ${LOCAL_IMAGE_TAG}