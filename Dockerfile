# Tooling is the base iamge for the build scripts and is carried into the final output
# Tooling is one of the default cached stages (CACHED_STAGES)
FROM openjdk:11-jdk as tooling
ENV DEBIAN_FRONTEND noninteractive  # Needed when using APT
WORKDIR /src
COPY ./gradlew ./settings.gradle ./gradle.properties /src/
COPY ./gradle /src/gradle
ARG NEXUS_PROXY="http://ops.pointivo.net:8081/repository/pointivo/"
ENV NEXUS_PROXY=$NEXUS_PROXY
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    ./gradlew


# Runtime is the base image for application
# Runtume is one of the default cached stages (CACHED_STAGES)
FROM openjdk:11-jre-slim as runtime
ENV DEBIAN_FRONTEND noninteractive   # Needed when using APT
WORKDIR /app
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -ms /bin/bash pv && \
    chown pv .
USER pv


# Depencies is one of the default cached stages (CACHED_STAGES)
FROM tooling as dependencies
COPY build.gradle /src/build.gradle
RUN ./gradlew dependencies


FROM dependencies as build
ARG SEMVER
ENV SEMVER=$SEMVER
ARG gradleTargets='build bootJar'
RUN ./gradlew $gradleTargets -b build.gradle -Psemver=$SEMVER; \
    echo $? > /src/build/build_status # Save build exit status so that test-results can be published


# Use runtime stage image for final output
FROM runtime as core-api
# Copy the executables --from the BUILD stage to keep container lightweight:
COPY --chown=pv --from=build /src/com.pointivo.core.api/build/libs/com.pointivo.core.api*.jar ./core-api.jar
COPY --chown=pv --from=build /src/com.pointivo.core.api/core-api.sh ./core-api.sh
EXPOSE 8080  #  Documentation for the default port the application listens on
CMD ["bash", "./core-api.sh"]


# Collect test reports
FROM scratch as reports
COPY --from=build /src/build/coverage* /reports
COPY --from=build /src/build/test-results* /test-results
COPY --from=build /src/build/build_status /build_status
