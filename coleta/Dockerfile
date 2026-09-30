ARG BASE_IMAGE=utils-r_duckdb:latest
FROM ${BASE_IMAGE}

# Dependências de sistema para sf/geobr (GDAL, GEOS, PROJ)
RUN apt-mark hold r-base r-base-core r-base-dev r-recommended 2>/dev/null || true && \
    apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libudunits2-dev \
    libssl-dev \
    libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/*

# Instala dependências específicas
RUN R -q -e "pkgs <- c('sf', 'geobr'); \
             install.packages(pkgs); \
             stopifnot(all(pkgs %in% rownames(installed.packages())))"

# Diretório de trabalho
WORKDIR /app

# Copia utilitários
COPY dags/utils/utils.R .

# Copia a pasta de coleta
COPY dags/base_faixa_litoranea/coleta/ .

# Cache do geobr em área gravável
ENV GEOBR_CACHE_DIR=/tmp/geobr_cache

# Executa
CMD ["Rscript", "coleta.R"]
