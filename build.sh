set -e
set -x

if [ -z "${IMAGE_NAME}" ]; then
  echo "Missing required ENV variables; Exiting." && exit 1
fi

# Script Variables / Defaults
EXTRA_BUILD_ARGS=${EXTRA_BUILD_ARGS:-""}
DOCKERFILE_DIRECTORY=${DOCKERFILE_DIRECTORY:-"./"}
DOCKERFILE_NAME=${DOCKERFILE_NAME:-"Dockerfile"}
ARTIFACT_PATHS=${ARTIFACT_PATHS:-"/test-results,/reports,/build_status"}
CACHED_STAGES=${CACHED_STAGES:-"tooling,runtime,dependencies"}
BUILD_STAGE=${BUILD_STAGE:-"build"}
RELEASE_STAGE=${RELEASE_STAGE:-$IMAGE_NAME}
PULL_IMAGES=${PULL_IMAGES:-""}
CACHE_LAYER_PREFIX=${CACHE_LAYER_PREFIX:-$IMAGE_NAME}
BUILD_IMAGE_NAME="${CACHE_LAYER_PREFIX}_build"
SEMVER=${SEMVER:-1.0.0}
dockerfile_directory=${DOCKERFILE_DIRECTORY:-./}
dockerfile_name=${DOCKERFILE_NAME:-Dockerfile}
DOCKERFILE="${dockerfile_directory%/}/${dockerfile_name}"
GIT_SHA_SHORT=$(git rev-parse --short HEAD)
RELEASE_TAG=${RELEASE_TAG:-"release"}
IMAGE_TAG="${IMAGE_NAME}:${SEMVER}_${RELEASE_TAG}.${GIT_SHA_SHORT}"
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
  docker build ${stage_prefix}  \
    --target ${_stage} \
    -t "${CACHE_LAYER_PREFIX}_${_stage}" \
    --build-arg SEMVER="${SEMVER}" \
    ${EXTRA_BUILD_ARGS} \
    -f ${DOCKERFILE} \
    ./
}

build_final() {
  _stage=${1}
  _tag=${2}
  echo "Building final stage: ${_stage}"
  docker build \
    --squash \
    -t "${_tag}" \
    --target ${_stage} \
    --build-arg SEMVER="${SEMVER}" \
    ${EXTRA_BUILD_ARGS} \
    -f ${DOCKERFILE} \
    ./
}

export_reports() {
  mkdir -p ./build
  id=$(docker create ${BUILD_IMAGE_NAME})
  for _path in ${ARTIFACT_PATHS//,/ }; do
    docker cp $id:${_path} ./build${_path} || true
  done
  docker rm $id
}

on_exit() {
  ret_code=$?
  docker rmi --force ${BUILD_IMAGE_NAME}
  exit $ret_code
}

###############
# Warmup
###############

# Refresh Images
echo "Pulling latest images..."
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
build_final ${RELEASE_STAGE} ${IMAGE_TAG}
