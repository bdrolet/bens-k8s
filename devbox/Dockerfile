FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    less \
    openssh-client \
    unzip \
    vim \
    wget \
  && rm -rf /var/lib/apt/lists/*

# kubectl (latest stable)
RUN KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) \
  && curl -fsSLo /usr/local/bin/kubectl \
     "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  && chmod +x /usr/local/bin/kubectl

# helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

RUN useradd -m -s /bin/bash -u 1000 devuser \
  && mkdir -p /workspace \
  && chown devuser:devuser /workspace

USER devuser
WORKDIR /workspace

CMD ["sleep", "infinity"]
