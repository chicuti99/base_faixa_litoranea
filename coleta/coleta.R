#!/usr/bin/env Rscript

# Dominio: base_faixa_litoranea
# Descricao: materializa na bronze o limite estadual do ES (silver do
#            base_geobr) e os limites dos estados vizinhos (BA, MG, RJ),
#            obtidos diretamente via geobr. Os vizinhos sao necessarios para
#            distinguir, no pre-processamento, qual parte do perimetro do ES
#            e fronteira terrestre e qual e litoral.

library(geobr)
library(sf)

source("utils.R")

valor_ambiente <- function(nome, padrao) {
  valor <- Sys.getenv(nome, unset = "")
  if (nzchar(valor)) valor else padrao
}

# geobr grava cache em disco; direciona para area gravavel do container
Sys.setenv(GEOBR_CACHE_DIR = "/tmp/geobr_cache")
dir.create("/tmp/geobr_cache", recursive = TRUE, showWarnings = FALSE)
options(timeout = max(600, getOption("timeout")))

ANO           <- as.integer(valor_ambiente("FAIXA_LITORANEA_GEOBR_ANO", "2020"))
UF            <- valor_ambiente("FAIXA_LITORANEA_UF", "ES")
UFS_VIZINHAS  <- trimws(strsplit(valor_ambiente("FAIXA_LITORANEA_UFS_VIZINHAS", "BA,MG,RJ"), ",")[[1]])
ESTADO_PREFIX <- valor_ambiente("FAIXA_LITORANEA_GEOBR_ESTADO_PREFIX", "silver/base_geobr/malha_estado/")
ESTADO_CRS    <- as.integer(valor_ambiente("FAIXA_LITORANEA_GEOBR_ESTADO_CRS", "4674"))

# Converte objeto sf em data.frame serializavel em parquet (mesma convencao
# do base_geobr: geometria como WKT, CRS preservado em coluna propria).
sf_para_df <- function(obj) {
  df <- sf::st_drop_geometry(obj)
  df$geometry_wkt <- sf::st_as_text(sf::st_geometry(obj))
  df$crs_epsg     <- sf::st_crs(obj)$epsg
  df$data_coleta  <- Sys.Date()
  return(df)
}

coletar_estado <- function() {
  cat("[COLETA] Lendo limite estadual do ES em", ESTADO_PREFIX, "\n")

  estado <- read_latest_parquet_from_minio(ESTADO_PREFIX)
  if (is.null(estado) || nrow(estado) == 0) {
    stop(sprintf("Nenhum dado encontrado em %s", ESTADO_PREFIX))
  }

  crs <- if ("crs_epsg" %in% names(estado) && !is.na(estado$crs_epsg[1])) {
    estado$crs_epsg[1]
  } else {
    ESTADO_CRS
  }
  estado_sf <- sf::st_as_sf(estado, wkt = "geometry_wkt", crs = crs)

  cat("[COLETA] Limite estadual do ES lido com sucesso\n")
  estado_sf
}

coletar_vizinhos <- function() {
  cat("[COLETA] Buscando estados vizinhos via geobr:", paste(UFS_VIZINHAS, collapse = ", "), "\n")

  vizinhos <- lapply(UFS_VIZINHAS, function(uf) {
    cat("[COLETA] Baixando limite estadual:", uf, "\n")
    geobr::read_state(code_state = uf, year = ANO)
  })

  vizinhos_sf <- do.call(rbind, vizinhos)
  if (is.null(vizinhos_sf) || nrow(vizinhos_sf) == 0) {
    stop("Nenhum estado vizinho retornado pelo geobr")
  }

  cat("[COLETA] Estados vizinhos coletados:", nrow(vizinhos_sf), "\n")
  vizinhos_sf
}

coleta <- function() {
  cat("[COLETA] Buscando malha do", UF, "e vizinhos", paste(UFS_VIZINHAS, collapse = ", "), "\n")

  tryCatch({
    list(
      malha_estado    = sf_para_df(coletar_estado()),
      malha_vizinhos  = sf_para_df(coletar_vizinhos())
    )
  }, error = function(e) {
    cat("[COLETA] Erro ao coletar dados:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

save_data <- function(dados) {
  cat("[COLETA] Salvando dados no MinIO via DuckDB\n")

  tryCatch({
    timestamp <- format(Sys.time(), "%Y%m%d")
    caminhos <- character(0)

    for (nome_camada in names(dados)) {
      filepath <- sprintf(
        "bronze/base_faixa_litoranea/%s/%s_%s.parquet",
        nome_camada, nome_camada, timestamp
      )

      write_parquet_to_minio(dados[[nome_camada]], filepath)

      cat("[COLETA] Camada salva:", filepath,
          "| registros:", nrow(dados[[nome_camada]]), "\n")
      caminhos <- c(caminhos, filepath)
    }

    return(caminhos)

  }, error = function(e) {
    cat("[COLETA] Erro ao salvar no MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

tryCatch({
  cat("============================================================\n")
  cat("[COLETA] Coleta iniciada! Dominio: base_faixa_litoranea\n")
  cat("============================================================\n")

  data <- coleta()
  filepath <- save_data(data)

  cat("============================================================\n")
  cat("[COLETA] Coleta finalizada com sucesso!\n")
  cat("[COLETA] Arquivos:", paste(filepath, collapse = " | "), "\n")
  cat("============================================================\n")

}, error = function(e) {
  cat("[COLETA] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})
