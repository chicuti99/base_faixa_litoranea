FROM utils-r_duckdb:latest

# Instala dependências específicas (se necessário)
RUN R -e "install.packages(c('jsonlite'), repos='https://cloud.r-project.org/')"

# Diretório de trabalho
WORKDIR /app

# Copia utilitários
COPY dags/utils/utils.R .

# Copia a pasta de coleta
COPY dags/dag_template/coleta/ .

# Executa
CMD ["Rscript", "coleta.R"]