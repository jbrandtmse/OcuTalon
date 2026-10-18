# One recipe for every install: the build 154 image plus OcuTalon's merge file, manifest and health check.
# IRIS_IMAGE selects the base; the install script retags whichever archive was loaded to this name.
ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
# The mount directory is owned by the IRIS user (UID 51773), so a fresh named volume inherits that ownership.
RUN mkdir -p /durable && chown 51773:51773 /durable

COPY docker/merge.cpf src/module.xml docker/healthcheck.sh /opt/ocutalon/
# The image's version is the first <Version> of the manifest; an empty one fails the build.
RUN version="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' /opt/ocutalon/module.xml | head -n 1)" \
 && test -n "$version" \
 && printf '%s\n' "$version" > /opt/ocutalon/version \
 && chmod 444 /opt/ocutalon/merge.cpf /opt/ocutalon/module.xml /opt/ocutalon/version \
 && chmod 555 /opt/ocutalon/healthcheck.sh

USER 51773
ENV ISC_DATA_DIRECTORY=/durable/iris \
    ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf
