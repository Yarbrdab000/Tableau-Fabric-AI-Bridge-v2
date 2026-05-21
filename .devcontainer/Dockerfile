FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && apt-get install -y curl apt-transport-https gnupg lsb-release python3 python3-pip \
    && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y powershell git-lfs \
    && git lfs install --system \
    && rm /tmp/packages-microsoft-prod.deb
