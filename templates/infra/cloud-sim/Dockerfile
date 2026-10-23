# The image every job runs in, built from the repository root by sim_queue.yml:
#   docker build -f infra/cloud-sim/Dockerfile --build-arg GIT_SHA=<commit> .
#
# Pin exact versions of everything numerical. A result computed here should be comparable with one computed on the
# laptop, and changing a version changes the instrument.
FROM python:3.12.10-slim

# The AWS CLI, in its own environment so that its pinned dependencies cannot move the project's.
RUN python -m venv /opt/awscli \
 && /opt/awscli/bin/pip install --no-cache-dir awscli==1.34.0 \
 && ln -s /opt/awscli/bin/aws /usr/local/bin/aws

WORKDIR /app

# The project's dependencies. requirements.txt may be empty, but it must exist.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# If the runners import the project's own package, copy and install it too, for example:
#   COPY pyproject.toml ./
#   COPY src ./src
#   RUN pip install --no-cache-dir --no-deps -e .

COPY scripts ./scripts
COPY configs ./configs
COPY infra/cloud-sim/run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

# The commit this image was built from, recorded in every run's _run.json.
ARG GIT_SHA=unknown
ENV SIM_IMAGE_COMMIT=$GIT_SHA

ENTRYPOINT ["/usr/local/bin/run.sh"]
