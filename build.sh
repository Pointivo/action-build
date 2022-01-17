set -e
set -x

if [ -z "${IMAGE_NAME}" ]; then
  echo "Missing required ENV variables; Exiting." && exit 1
fi

# Script Variables / Defaults
#EXTRA_BUILD_ARGS
#DOCKERFILE_DIRECTORY
#DOCKERFILE_NAME
#CACHED_STAGES
#BUILD_STAGE
#PULL_IMAGES
#RELEASE_TAG
RELEASE_STAGE=${RELEASE_STAGE:-$IMAGE_NAME}
CACHE_LAYER_PREFIX=${CACHE_LAYER_PREFIX:-$IMAGE_NAME}
BUILD_IMAGE_NAME="${CACHE_LAYER_PREFIX}_${BUILD_STAGE}"
DOCKERFILE="${DOCKERFILE_DIRECTORY%/}/${DOCKERFILE_NAME}"

GIT_SHA_SHORT=$(git rev-parse --short HEAD)
REPOSITORY=${REPOSITORY:-$IMAGE_NAME}
SEMVER=$(./version.sh -g)
# Validate SEMVER
semver diff ${SEMVER} ${SEMVER}
FULL_SEMVER="${SEMVER}-${RELEASE_TAG}+GH${GITHUB_RUN_NUMBER}.${GIT_SHA_SHORT}"
IMAGE_TAG="${SEMVER}_${RELEASE_TAG}_GH${GITHUB_RUN_NUMBER}.${GIT_SHA_SHORT}"

echo "Dockerfile: ${DOCKERFILE}"
echo "Git commit hash: ${GIT_SHA_SHORT}"
echo "Stages to cache: ${CACHED_STAGES}"
echo "build_args: ${build_args}"
echo "Semver: ${SEMVER}"
echo "Full Semver: ${FULL_SEMVER}"
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
  command+="--build-arg SEMVER=\"${FULL_SEMVER}\" "
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
  command+="--build-arg SEMVER=\"${FULL_SEMVER}\" "
  command+="${EXTRA_BUILD_ARGS} "
  command+="-f \"${DOCKERFILE}\" "
  command+="./"
  eval $command
}

export_artifacts() {
  echo "Exporting Test/Reports: ${TEST_PATH}"
  mkdir -p ./build/artifacts
  id=$(docker create ${BUILD_IMAGE_NAME} /bin/sh)
  if [[ -n "${TEST_PATH}" ]]; then
     docker cp $id:${TEST_PATH} ./build/artifacts/test-results || true
     echo "Test results exported"
  fi
  if [[ -n "${BUILD_STATUS_PATH}" ]]; then
     docker cp $id:${BUILD_STATUS_PATH} ./build/build_status || true
     echo "Exported build status"
  fi
  docker rm $id
}

on_exit() {
  ret_code=$?
  echo "Deleting build image: ${BUILD_IMAGE_NAME}"
  docker rmi --force ${BUILD_IMAGE_NAME} || true
  # docker system prune? The cache images sometime don't get removed and subsequent builds will still use cache
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
export_artifacts

status_file=./build/build_status
if [ -f "${status_file}" ]; then
  status=$(cat ${status_file})
  if [ ${status} -ne 0 ]; then
    exit ${status}
  fi
fi

# Build Final Target
build_final ${RELEASE_STAGE} "${REPOSITORY}:${IMAGE_TAG}"
