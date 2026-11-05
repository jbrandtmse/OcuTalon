# One recipe for every install: the build 154 image plus OcuTalon's merge file, sources, pinned IPM release,
# after-start script and health check. The package installs at every start, not at build (AD-23).
# IRIS_IMAGE selects the base; the install script retags whichever archive was loaded to this name.
ARG IRIS_IMAGE=ocutalon-iris-base:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
# The mount directory is owned by the IRIS user (UID 51773), so a fresh named volume inherits that ownership.
RUN mkdir -p /durable && chown 51773:51773 /durable

# Step 3's Python packages and embedding model (AD-21, AD-23), before the sources so that a source change reuses this layer. One pinned
# pip line installs fastembed, pdfplumber and python-docx with their dependencies, wheels only, where IRIS's Python imports them.
# The licence gate then lists every installed distribution with its licence and fails the build on any outside the allowed set
# (docker/licences/allowed.txt), and the notices file is written from the installed licence files; no licence file is deleted.
# The model AllMiniLM-L6-v2 is downloaded now, so that no first use needs the network, into a root-owned read-only folder that
# FASTEMBED_CACHE_DIR names (files 444, folders 555); it sits outside /opt/ocutalon so that the mode step below never copies it again.
COPY docker/licences/ /opt/ocutalon/licences/
RUN python3 -m pip install --break-system-packages --no-cache-dir --target /usr/irissys/mgr/python --only-binary=:all: fastembed==0.9.0 pdfplumber==0.11.10 python-docx==1.1.2 \
 && python3 /opt/ocutalon/licences/gate.py check /usr/irissys/mgr/python \
 && python3 /opt/ocutalon/licences/gate.py notices /usr/irissys/mgr/python /opt/ocutalon/THIRD-PARTY-NOTICES \
 && mkdir -p /opt/fastembed \
 && PYTHONPATH=/usr/irissys/mgr/python HF_HUB_DISABLE_TELEMETRY=1 python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qdrant/all-MiniLM-L6-v2-onnx', cache_dir='/opt/fastembed', allow_patterns=['config.json', 'tokenizer.json', 'tokenizer_config.json', 'special_tokens_map.json', '*.onnx'])" \
 && chown -R root:root /opt/fastembed \
 && find /opt/fastembed -type d -exec chmod 555 {} + \
 && find /opt/fastembed -type f -exec chmod 444 {} +

COPY src/ /opt/ocutalon/src/
COPY docker/ipm/ /opt/ocutalon/ipm/
COPY docker/merge.cpf docker/healthcheck.sh docker/after-start.sh docker/after-start.cos /opt/ocutalon/
# The image's version is the first <Version> of the manifest; an empty one fails the build, and so does a source
# tree without the web bundle that npm --prefix web run build writes.
# Everything is root's and read-only: files 444, directories and the two scripts 555.
RUN version="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' /opt/ocutalon/src/module.xml | head -n 1)" \
 && test -n "$version" \
 && { test -f /opt/ocutalon/src/ocutalon/csp/index.html || { echo "web bundle missing: run npm --prefix web run build" >&2; exit 1; }; } \
 && printf '%s\n' "$version" > /opt/ocutalon/version \
 && find /opt/ocutalon -type f -exec chmod 444 {} + \
 && find /opt/ocutalon -type d -exec chmod 555 {} + \
 && chmod 555 /opt/ocutalon/healthcheck.sh /opt/ocutalon/after-start.sh

USER 51773
ENV ISC_DATA_DIRECTORY=/durable/iris \
    ISC_CPF_MERGE_FILE=/opt/ocutalon/merge.cpf \
    FASTEMBED_CACHE_DIR=/opt/fastembed
# iris-main deletes the ready marker before IRIS starts, so no health probe of this start sees the previous
# start's marker, then runs the after-start script once IRIS is up.
CMD ["--before", "rm -f /durable/ocutalon.ready", "--after", "/opt/ocutalon/after-start.sh"]
