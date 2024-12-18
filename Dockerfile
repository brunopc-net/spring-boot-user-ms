# Pinning the exact java version, resulting in the same result in every container
FROM eclipse-temurin:21.0.5_11-jdk-noble AS build-image

WORKDIR /app

ARG GRADLE_VERSION=8.11.1 \
    GRADLE_CHECKSUM=f397b287023acdba1e9f6fc5ea72d22dd63669d59ed4a289a29b1a76eee151c6
    # You can verify checksum at https://gradle.org/release-checksums

# Install Gradle
RUN set -o errexit -o nounset \
    && wget --no-verbose --output-document=gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
    && echo "${GRADLE_CHECKSUM} gradle.zip" | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends unzip \
    && unzip -q gradle.zip -d /opt/ \
    && rm gradle.zip \
    && ln -s "/opt/gradle-${GRADLE_VERSION}/bin/gradle" /usr/bin/gradle \
    && gradle --version

# Build the application
COPY build.gradle settings.gradle ./
COPY src ./src
RUN ls -lrt
RUN gradle clean build -x test

# Producing a custom JRE using jlink
RUN set -o errexit -o nounset \
    && unzip -q build/libs/app.jar \
    && jdeps --ignore-missing-deps -q  \
        --recursive  \
        --multi-release 21  \
        --print-module-deps  \
        --class-path 'BOOT-INF/lib/*'  \
        build/libs/app.jar > deps.info \
    && jlink \
        --add-modules $(cat deps.info) \
        --strip-debug \
        --no-man-pages \
        --no-header-files \
        --compress zip-6 \
        --output jre-custom

#######################################################################################################################
# Stage 2: Create the final image
# Using Ubuntu: better choice for most use cases. Why?
# 1- Way more reliable than Alpine for production.
#    Sometimes, Alpine has weird compatibility problems and production failure stories. Packages are not pinable in Alpine
# 2- More usable then Distroless. We have a shell, we can debug much better.
#    Distroless may be the best image for final ppr/prod release when you're 100% sure of the stability, not before
# 3- Debian? At the time of writing, Ubuntu has fewer CVEs (0 vs vs 1 med, 23 low)
#######################################################################################################################

# Pinning the exact Ubuntu version, resulting in the same result in every container
FROM ubuntu:oracular-20241120
# FROM ubuntu:noble-20241118.1 Noble (24.04) is the latest LTS, but has some CVEs - 2 medium and 5 low as of now

# Package install (uncomment if needed)
# RUN apt-get update && apt-get install -y \
#    package1=1.2.3 \
#    package2=2.3.4

#Running as non-root
WORKDIR /home/ubuntu
USER ubuntu

# Copy the application JAR file from the build stage
COPY --from=build-image app/build/libs/app.jar app.jar

# "Installing" Java by copying the custom JRE from the build stage
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"
COPY --from=build-image app/jre-custom $JAVA_HOME
RUN set -eux && java --version

# Expose the application port
EXPOSE 8080

HEALTHCHECK CMD curl -f http://localhost:8080/ || exit 1

# Command to run the application
ENTRYPOINT ["java", "-jar", "app.jar"]