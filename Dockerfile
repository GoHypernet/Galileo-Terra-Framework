# get the Galileo IDE
FROM hypernetlabs/galileo-ide:linux AS galileo-ide

# add galileo non-root user
RUN useradd -ms /bin/bash galileo
USER galileo

RUN mkdir -p /home/galileo/.terrad/config && \
    curl https://columbus-genesis.s3-ap-northeast-1.amazonaws.com/columbus-4-genesis.json > /home/galileo/.terrad/config/genesis.json && \
    curl https://network.terra.dev/addrbook.json > /home/galileo/.terrad/config/addrbook.json

# get the go executable 
FROM golang as go-build

RUN git clone https://github.com/terra-money/core
RUN cd core && git checkout master && make install
	
# Final build stage
FROM ubuntu:18.04

# install geth, python, node, and smart contract development tooling
RUN apt update -y \
  && apt install -y software-properties-common gpg \
  && add-apt-repository -y ppa:deadsnakes/ppa \
  && apt update -y \
  && apt install -y \
    supervisor \
    python3.8 python3-pip python3.8-dev \
    libsecret-1-dev \
	vim curl tmux git zip unzip vim speedometer net-tools \
  && python3.8 -m pip install web3 py-solc py-solc-x \
  && curl -fsSL https://deb.nodesource.com/setup_12.x | bash - \
  && apt install -y nodejs \
  && npm install -g solc \
  && curl https://rclone.org/install.sh | bash \
  && rm -rf /var/lib/apt/lists/*

# get the go runtime
COPY --from=go-build /go /go
COPY --from=go-build /usr/local/go /usr/local/go
COPY --from=go-build /go/bin/terra* /usr/bin/.
ENV PATH $PATH:/usr/local/go/bin:/home/galileo:/home/galileo/.local/bin
ENV GOPATH /usr/local/go

RUN go get -u github.com/bitnami/bcrypt-cli

# add galileo non-root user
RUN useradd -ms /bin/bash galileo

COPY --chown=galileo .theia /home/galileo/.theia
COPY --chown=galileo .vscode /home/galileo/.vscode
COPY --chown=galileo runterrad.sh /home/galileo/runterrad.sh

# get the Caddy server executables and stuff
COPY --from=galileo-ide --chown=galileo /caddy/caddy /usr/bin/caddy
COPY --from=galileo-ide --chown=galileo /caddy/header.html /etc/assets/header.html
COPY --from=galileo-ide --chown=galileo /caddy/users.json /etc/gatekeeper/users.json
COPY --from=galileo-ide --chown=galileo /caddy/auth.txt /etc/gatekeeper/auth.txt
COPY --from=galileo-ide --chown=galileo /caddy/settings.template /etc/gatekeeper/assets/settings.template
COPY --from=galileo-ide --chown=galileo /caddy/login.template /etc/gatekeeper/assets/login.template
COPY --from=galileo-ide --chown=galileo /caddy/custom.css /etc/gatekeeper/assets/custom.css

COPY --from=galileo-ide --chown=galileo /home/galileo/.terrad/config/genesis.json /home/galileo/.terrad/config/genesis.json
COPY --from=galileo-ide --chown=galileo /home/galileo/.terrad/config/addrbook.json /home/galileo/.terrad/config/addrbook.json

COPY --chown=galileo rclone.conf /home/galileo/.config/rclone/rclone.conf
COPY --chown=galileo Caddyfile /etc/

# get the galileo IDE
COPY --from=galileo-ide --chown=galileo /.galileo-ide /home/galileo/.galileo-ide

USER galileo
WORKDIR /home/galileo/.galileo-ide
	
# get supervisor configuration file
COPY --chown=galileo supervisord.conf /etc/

# set environment variable to look for plugins in the correct directory
ENV SHELL=/bin/bash \
    THEIA_DEFAULT_PLUGINS=local-dir:/home/galileo/.galileo-ide/plugins
ENV USE_LOCAL_GIT true
ENV GALILEO_RESULTS_DIR /home/galileo

# set login credentials and write them to text file
ENV USERNAME "a"
ENV PASSWORD "a"
RUN sed -i 's,"username": "","username": "'"$USERNAME"'",1' /etc/gatekeeper/users.json && \
    sed -i 's,"hash": "","hash": "'"$(echo -n "$(echo $PASSWORD)" | bcrypt-cli -c 10 )"'",1' /etc/gatekeeper/users.json

ENTRYPOINT ["sh", "-c", "supervisord"]