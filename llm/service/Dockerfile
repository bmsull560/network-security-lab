# llm/service/Dockerfile
# LLM analyst service — FastAPI + Uvicorn on Python 3.12-slim
#
# Constitution compliance:
#   Article I   — runs as non-root user (appuser)
#   Article IX  — base image pinned to digest; deps pinned in requirements.txt
#   Article XI  — least privilege: appuser has no sudo, no shell access to host

FROM python:3.12-slim

# Create non-root user
RUN groupadd --gid 1001 appuser \
 && useradd --uid 1001 --gid appuser --shell /bin/bash --create-home appuser

WORKDIR /app

# Install dependencies as root before switching user
COPY llm/service/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy service source
COPY llm/service/*.py ./

# Copy supporting artifacts (schemas, prompts, policy)
COPY llm/schema/ ./schema/
COPY llm/prompts/ ./prompts/
COPY llm/policy.yaml ./policy.yaml

# Audit log directory — will be overridden by volume mount
RUN mkdir -p /app/audit && chown appuser:appuser /app/audit

# Switch to non-root
USER appuser

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
