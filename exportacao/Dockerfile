ARG BASE_IMAGE=utils-r_duckdb:latest
FROM ${BASE_IMAGE}

# Diretório de trabalho
WORKDIR /app

# Copia utilitários
COPY dags/utils/utils.R .

# Copia o script
COPY dags/base_faixa_litoranea/exportacao/ .

# Executa
CMD ["Rscript", "exportacao.R"]
