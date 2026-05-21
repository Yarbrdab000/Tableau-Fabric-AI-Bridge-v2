FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y curl apt-transport-https gnupg \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && apt-get install -y powershell git-lfs \
    && git lfs install --system
