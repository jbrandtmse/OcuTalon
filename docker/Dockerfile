# One recipe for every install: the build 154 image plus OcuTalon's merge file, sources, pinned IPM release,
# after-start script and health check. The package installs at every start, not at build (AD-23).
# IRIS_IMAGE selects the base; the install script retags whichever archive was loaded to this name.
ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
# The mount directory is owned by the IRIS user (UID 51773), so a fresh named volume inherits that ownership.
RUN mkdir -p /durable && chown 51773:51773 /durable

COPY src/ /opt/ocutalon/src/
COPY docker/ipm/ /opt/ocutalon/ipm/
COPY docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos /opt/ocutalon/
# The image's version is the first <Version> of the manifest; an empty one fails the build.
# Everything is root's and read-only: files 444, directories and the two scripts 555.
RUN version="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' /opt/ocutalon/src/module.xml | head -n 1)" \
 && test -n "$version" \
 && printf '%s\n' "$version" > /opt/ocutalon/version \
 && find /opt/ocutalon -type f -exec chmod 444 {} + \
 && find /opt/ocutalon -type d -exec chmod 555 {} + \
 && chmod 555 /opt/ocutalon/healthcheck.sh /opt/ocutalon/after-start.sh

USER 51773
ENV ISC_DATA_DIRECTORY=/durable/iris \
    ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf
CMD ["--after", "/opt/ocutalon/after-start.sh"]
