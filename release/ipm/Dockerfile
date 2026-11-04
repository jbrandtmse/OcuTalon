# A clean instance like an admin's, for release/ipm-install.sh (Story 15.1; AD-23, FR-57): the build 154 base image plus the package
# sources and the pinned IPM release file, and nothing more. It has no merge file, no after-start script, no version file and no
# health check of its own, so the package's first run, not the image, creates OCUTALON.
ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
COPY src/ /opt/ocutalon-ipm/src/
COPY docker/ipm/zpm-0.10.10.xml /opt/ocutalon-ipm/
RUN find /opt/ocutalon-ipm -type f -exec chmod 444 {} + \
 && find /opt/ocutalon-ipm -type d -exec chmod 555 {} +
USER 51773
