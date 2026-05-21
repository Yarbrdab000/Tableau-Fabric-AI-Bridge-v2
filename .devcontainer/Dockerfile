FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && apt-get install -y powershell git-lfs \
    && git lfs install --system

RUN pip3 install requests azure-identity azure-keyvault-secrets --break-system-packages
