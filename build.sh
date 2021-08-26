set -e
set -x

if [ -z "${IMAGE_NAME}" ]; then
  echo "Missing required ENV variables; Exiting." && exit 1
fi

# Script Variables / Defaults
EXTRA_BUILD_ARGS=${EXTRA_BUILD_ARGS:-""}
DOCKERFILE_DIRECTORY=${DOCKERFILE_DIRECTORY:-"./"}
DOCKERFILE_NAME=${DOCKERFILE_NAME:-"Dockerfile"}
CACHED_STAGES=${CACHED_STAGES:-"tooling,runtime,dependencies"}
BUILD_STAGE=${BUILD_STAGE:-"build"}
RELEASE_STAGE=${RELEASE_STAGE:-$IMAGE_NAME}
PULL_IMAGES=${PULL_IMAGES:-""}
CACHE_LAYER_PREFIX=${CACHE_LAYER_PREFIX:-$IMAGE_NAME}
BUILD_IMAGE_NAME="${CACHE_LAYER_PREFIX}_build"
ARTIFACT_PATHS=${ARTIFACT_PATHS:-"/test-results,/reports,/build_status"}
ARTIFACT_STAGE=${ARTIFACT_STAGE:-$BUILD_IMAGE_NAME}
SEMVER=${SEMVER:-1.0.0}
dockerfile_directory=${DOCKERFILE_DIRECTORY:-./}
dockerfile_name=${DOCKERFILE_NAME:-Dockerfile}
DOCKERFILE="${dockerfile_directory%/}/${dockerfile_name}"
GIT_SHA_SHORT=$(git rev-parse --short HEAD)
RELEASE_TAG=${RELEASE_TAG:-"release"}
REPOSITORY=${REPOSITORY:-$IMAGE_NAME}
IMAGE_TAG="${SEMVER}_${RELEASE_TAG}.${GIT_SHA_SHORT}"
echo "Dockerfile: ${DOCKERFILE}"
echo "Git commit hash: ${GIT_SHA_SHORT}"
echo "Targets to cache: ${CACHED_STAGES}"
echo "build_args: ${build_args}"
echo "semver: ${SEMVER}"
# Validate SEMVER
semver diff ${SEMVER} ${SEMVER}
# Save ENV variables for downstream Github Action steps
echo "GIT_SHA_SHORT=${GIT_SHA_SHORT}" >> $GITHUB_ENV
echo "SEMVER=${SEMVER}" >> $GITHUB_ENV
echo "IMAGE_TAG=${IMAGE_TAG}" >> $GITHUB_ENV
echo "::set-output name=commitHash::${GIT_SHA_SHORT}"
echo "::set-output name=semver::${SEMVER}"
echo "::set-output name=imageTag::${IMAGE_TAG}"

export DOCKER_BUILDKIT=1

build_stage() {
  _stage=${1}
  echo "Building stage: ${_stage}"
  command="docker build "
  command+="--target \"${_stage}\" "
  command+="-t \"${CACHE_LAYER_PREFIX}_${_stage}\" "
  command+="--build-arg SEMVER=\"${SEMVER}\" "
  command+="${EXTRA_BUILD_ARGS} "
  command+="-f \"${DOCKERFILE}\" "
  command+="./"
  eval $command
}

build_final() {
  _stage=${1}
  _tag=${2}
  echo "Building final stage: ${_stage}"
  command="docker build "
  command+="--squash "
  command+="-t \"${_tag}\" "
  command+="--target \"${_stage}\" "
  command+="--build-arg SEMVER=\"${SEMVER}\" "
  command+="${EXTRA_BUILD_ARGS} "
  command+="-f \"${DOCKERFILE}\" "
  command+="./"
  eval $command
}

export_reports() {
  echo "Exporting Test/Reports: ${ARTIFACT_PATHS}"
  mkdir -p ./build
  id=$(docker create ${ARTIFACT_STAGE})
  for _path in ${ARTIFACT_PATHS//,/ }; do
    docker cp $id:${_path} ./build${_path} || true
  done
  docker rm $id
  echo "Done exporting tests"
}

on_exit() {
  ret_code=$?
  echo "Deleting build image: ${BUILD_IMAGE_NAME}"
  docker rmi --force ${BUILD_IMAGE_NAME}
  echo "Cleanup complete, exiting."
  exit $ret_code
}

###############
# Warmup
###############

# Refresh Images
echo "Pulling latest images: ${PULL_IMAGES}"
for _image in ${PULL_IMAGES//,/ }; do
  docker pull "${_image}"
done

###############
# Build
###############

# Building persistent stages
for stage in ${CACHED_STAGES//,/ }; do
  if grep -i -q "as ${stage}\$" "${DOCKERFILE}"; then
    build_stage $stage
  fi
done

# Build
build_stage ${BUILD_STAGE}
trap "on_exit" EXIT

# Export tests
export_reports

status_file=./build/build_status
if [ -f "${status_file}" ]; then
  status=$(cat ${status_file})
  if [ ${status} -ne 0 ]; then
    exit ${status}
  fi
fi

# Build Final Target
build_final ${RELEASE_STAGE} "${REPOSITORY}:${IMAGE_TAG}"
