FROM utils-r_duckdb:latest

# Instala dependências específicas (se necessário)
RUN R -e "install.packages(c('dplyr', 'data.table', 'stringr', 'tidyr', 'zoo'), repos='https://cloud.r-project.org/')"

# Diretório de trabalho
WORKDIR /app

# Copia utilitários
COPY dags/utils/utils.R .

# Copia o script
COPY dags/dag_template/processamento/ .

# Executa
CMD ["Rscript", "processamento.R"]