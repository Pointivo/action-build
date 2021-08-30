# Pointivo Action: Build

One build script to rule them all.

Sample: [Dockerfile TEMPLATE](Dockerfile_TEMPLATE)


## Environment Variables

### Required:
- **IMAGE_NAME** 
  - The name for the IMAGE when uploaded to the container registry. (Eg. `core-api`)
- **CACHED_STAGES** (Default: `tooling,runtime,dependencies`)
    - A comma seperated list of build stage (target) within your Dockerfile that can be cached between builds.
- **ARTIFACT_PATHS** (Default: `/test-results,/build_status`)
  - A comma seperated list of absolute paths where the files or folders for unit tests/reports and 
  build_status files are located.
  
### Optional:

- PULL_IMAGES (Default: None)
  - A comma seperated list of images to `docker pull` (to get latest) before building. Eg. `ubuntu:latest,node:lts`
- RELEASE_STAGE (Default: `$IMAGE_NAME`)
  - The Docker stage which builds the final container.
- BUILD_STAGE (Default: `build`)
  - An alternative build stage name (for mono-repos).
- EXTRA_BUILD_ARGS (Default: None)
  - These are extra arguments that you will be passed to `docker build`. Eg Gradle Build args `--build arg gradleTarget=...`
- DOCKERFILE_DIRECTORY (Default: `./`)
  - Use this if (in a monorepo) you have multiple docker files and there is a sub-directory where your Dockerfile is located.
- DOCKERFILE_NAME (Default: `Dockerfile`)
  - Use this if you use a different Docker file name.
- ARTIFACT_PATHS (Default: `/test-results,/reports,/build_status`)
  - A comma seperated list of files or directories which need to be exported as an artifact.
- RELEASE_TAG (Default: `snapshot`)
  - Override: This is used to specify the `prerelease` section of a full SEMVER which we tag our container images. Use depending on
  where the final output image will be deployed. `snapshot` implies master, `prerelease` implies qa`, `release` implies production.
- SEMVER
  - Override: This is, by default, grabbed from a file called `version.sh` in the root directory of the repository.
  

### Upload

This commits and replaces the tag so that all Github actions use the latest commit.

```bash
git add .
git commit -m "Update Action"
git push

git tag -fa -m "Updates to the Action" v1
git push origin master -f --tags
```