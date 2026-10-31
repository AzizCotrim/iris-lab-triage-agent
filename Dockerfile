ARG IMAGE=irishealth-community:2026.3.0AI.154.0
FROM $IMAGE

WORKDIR /home/irisowner/dev

ARG NAMESPACE="IRISAPP"
ENV IRISUSERNAME="_SYSTEM"
ENV IRISPASSWORD="SYS"
ENV IRISNAMESPACE=$NAMESPACE

COPY merge.cpf /home/irisowner/dev/merge.cpf

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
    iris session IRIS < iris.script && \
    iris stop IRIS quietly

# iris-main writes iris-main.log in its cwd; /home/irisowner/dev is the bind-mounted repo,
# which irisowner (uid 51773) cannot write on a fresh clone.
WORKDIR /home/irisowner
