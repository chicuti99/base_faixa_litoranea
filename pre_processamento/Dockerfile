FROM utils-r_duckdb:latest

# Instala dependências específicas (se necessário)
# RUN R -e "install.packages(c(''), repos='https://cloud.r-project.org/')"

# Diretório de trabalho
WORKDIR /app

# Copia utilitários
COPY dags/utils/utils.R .

# Copia o script
COPY dags/dag_template/pre_processamento/ .

# Executa
CMD ["Rscript", "pre_processamento.R"]