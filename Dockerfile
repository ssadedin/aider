# Dockerfile — JupyterLab + BeakerX + Aider all-in-one image
#
# Layers Aider (AI pair programming) on top of jupyterlab-ai-groovy.
# Installs from local source with all extras (playwright, help, browser).
#
# Build context: this (aider) repository root.
#
# Image stack:
#   jupyterlab-ai-base      → JupyterLab 3.2.x + Python science stack + Java/Groovy
#     └─ jupyterlab-ai-groovy → BeakerX kernels + widgets
#          └─ jupyterlab-ai-aider (this) → Aider AI coding assistant

FROM jupyterlab-ai-groovy

# System deps required by Aider (git & build-essential already in base)
RUN apt-get update && \
    apt-get install -y --no-install-recommends libportaudio2 pandoc && \
    rm -rf /var/lib/apt/lists/*

# Copy aider source from build context (the aider repo itself)
COPY . /tmp/aider

# Constrain only the critical jupyter/beakerx packages so aider's install
# cannot upgrade them (which would break the jupyter stack). Everything else
# (numpy, scipy, etc.) is allowed to change to satisfy aider's needs.
RUN pip freeze | grep -v '^\(-e\|@\|#\)' | \
    grep -iE '^(jupyterlab|jupyter-server|jupyter-client|jupyter-core|tornado|traitlets|nbclassic|notebook|nbformat|nbconvert|ipykernel|ipython|setuptools)==' \
    > /tmp/constraints.txt

# Upgrade pip first (base image has 23.x which can silently fail on modern packages).
# Cap below 24 to avoid PEP 660 issues with the editable jupyterlab install.
RUN pip install --upgrade "pip>=23.3,<24"

# Install aider from source with all extras.
# Keep the compiled requirements (.txt) for version accuracy, but relax the
# specific pins that fail on aarch64:
#   - grpcio==1.76.0 conflicts with litellm's <1.68.0 requirement
#   - scikit-learn==1.8.0 has no aarch64 wheel
#   - torch pinned versions may not match our pre-installed CPU-only build
# Set SETUPTOOLS_SCM_PRETEND_VERSION so setuptools_scm doesn't fail if git
# tags are unreachable inside the Docker build.
# Use --extra-index-url for CPU-only torch wheels.
RUN cd /tmp/aider && \
    sed -i 's/^anyio==.*/anyio>=3.1.0,<4/' requirements.txt requirements/requirements-help.txt && \
    sed -i 's/^grpcio==.*/grpcio>=1.62.3,<1.68.0/' requirements.txt && \
    sed -i 's/^scikit-learn==.*/scikit-learn/' requirements/requirements-help.txt && \
    sed -i '/^nvidia-/d' requirements/requirements-help.txt && \
    sed -i '/^triton==/d' requirements/requirements-help.txt && \
    sed -i 's/^torch==.*/torch/' requirements/requirements-help.txt && \
    SETUPTOOLS_SCM_PRETEND_VERSION=0.1.0 \
    pip install -c /tmp/constraints.txt \
        --no-cache-dir \
        ".[help,browser,playwright]" \
        boto3 \
        google-cloud-aiplatform \
        --extra-index-url https://download.pytorch.org/whl/cpu && \
    rm -rf /tmp/aider /tmp/constraints.txt

# Aider's deps pull in setuptools 80+ which drops pkg_resources.
# Reinstall a version that includes it (beakerx needs pkg_resources at import time).
RUN pip install --force-reinstall "setuptools<69"

# Install Playwright chromium browser + system deps
RUN python -m playwright install --with-deps chromium

# Configure git safe directory for aider's git operations
RUN git config --system --add safe.directory '*'

# Playwright browser settings
ENV PLAYWRIGHT_BROWSERS_PATH=/root/pw-browsers
ENV PLAYWRIGHT_SKIP_BROWSER_GC=1

# Use bash as default shell in JupyterLab terminals (terminado reads SHELL)
ENV SHELL=/bin/bash
# TERM=ansi works best with Aider inside JupyterLab terminals
ENV TERM=ansi

# Install aider-lab launcher script
COPY aider-lab /usr/local/bin/aider-lab

# Verify aider is installed
RUN aider --version || true

EXPOSE 8888

CMD ["jupyter", "lab", "--dev-mode", "--extensions-in-dev-mode", "--ip=0.0.0.0", "--port=8888", "--allow-root", "--no-browser", "--NotebookApp.token=''"]
