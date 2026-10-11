FROM python@sha256:a1165e272e578941b84abc79e4ab38a0305cd12803a5c4247979ac7655f4d641
ENV DEBIAN_FRONTEND=noninteractive PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 MPLBACKEND=Agg HOME=/tmp/home MPLCONFIGDIR=/tmp/matplotlib
RUN apt-get update && apt-get install -y --no-install-recommends libreoffice-writer libreoffice-calc libreoffice-impress fonts-dejavu-core fonts-liberation && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /runner/requirements.txt
COPY requirements.lock /runner/requirements.lock
RUN pip install --no-cache-dir -r /runner/requirements.lock && pip freeze > /runner/installed-packages.txt
COPY assistant.py /usr/local/lib/python3.13/site-packages/assistant.py
COPY entry.py user_entry.py inspect_document.py /runner/
WORKDIR /outputs
USER 65532:65532
ENTRYPOINT ["python", "-I", "/runner/entry.py"]
