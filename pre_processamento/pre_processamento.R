#!/usr/bin/env Rscript

# Dominio: base_faixa_litoranea
# Descricao: a partir do perimetro do ES e dos estados vizinhos (bronze),
#            isola os trechos do perimetro que NAO sao fronteira terrestre
#            (compartilhada com BA, MG ou RJ) -- o que sobra e a linha de
#            costa. Em seguida gera o poligono de buffer de N km a partir
#            dessa linha. Todo o calculo geometrico (buffer, distancia)
#            precisa de um CRS metrico, por isso a silver deste dominio
#            trafega em CRS projetado (UTM), diferente da convencao do
#            base_geobr (que mantem a silver em graus/SIRGAS 2000).

library(sf)

source("utils.R")

valor_ambiente <- function(nome, padrao) {
  valor <- Sys.getenv(nome, unset = "")
  if (nzchar(valor)) valor else padrao
}

CRS_METRICO       <- as.integer(valor_ambiente("FAIXA_LITORANEA_CRS_METRICO", "31984"))
TOLERANCIA_M      <- as.numeric(valor_ambiente("FAIXA_LITORANEA_TOLERANCIA_FRONTEIRA_M", "500"))
BUFFER_M          <- as.numeric(valor_ambiente("FAIXA_LITORANEA_BUFFER_M", "5000"))
CRS_PADRAO_BRONZE <- as.integer(valor_ambiente("FAIXA_LITORANEA_GEOBR_ESTADO_CRS", "4674"))

df_para_sf <- function(df, crs_padrao = CRS_PADRAO_BRONZE) {
  crs <- if ("crs_epsg" %in% names(df) && !is.na(df$crs_epsg[1])) {
    df$crs_epsg[1]
  } else {
    crs_padrao
  }
  sf::st_as_sf(df, wkt = "geometry_wkt", crs = crs)
}

sf_para_df <- function(obj) {
  df <- sf::st_drop_geometry(obj)
  df$geometry_wkt <- sf::st_as_text(sf::st_geometry(obj))
  df$crs_epsg     <- sf::st_crs(obj)$epsg
  return(df)
}

read_data <- function() {
  cat("[PRE-PROCESSAMENTO] Lendo dados do MinIO via DuckDB\n")

  tryCatch({
    estado   <- read_latest_parquet_from_minio("bronze/base_faixa_litoranea/malha_estado/")
    vizinhos <- read_latest_parquet_from_minio("bronze/base_faixa_litoranea/malha_vizinhos/")

    if (is.null(estado) || nrow(estado) == 0) {
      stop("Base de entrada vazia: malha_estado")
    }
    if (is.null(vizinhos) || nrow(vizinhos) == 0) {
      stop("Base de entrada vazia: malha_vizinhos")
    }

    cat("[PRE-PROCESSAMENTO] Estado lido:", nrow(estado), "\n")
    cat("[PRE-PROCESSAMENTO] Vizinhos lidos:", nrow(vizinhos), "\n")

    return(list(estado = estado, vizinhos = vizinhos))

  }, error = function(e) {
    cat("[PRE-PROCESSAMENTO] Erro ao ler do MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# Isola os trechos do perimetro do estado que NAO estao proximos do perimetro
# dos vizinhos (fronteira terrestre) -- o que sobra e a linha de costa.
extrair_linha_costa <- function(estado, vizinhos) {
  cat("[PRE-PROCESSAMENTO] Isolando linha de costa (tolerancia:", TOLERANCIA_M, "m)\n")

  estado_m   <- sf::st_transform(sf::st_make_valid(estado), CRS_METRICO)
  vizinhos_m <- sf::st_transform(sf::st_make_valid(vizinhos), CRS_METRICO)

  perimetro_estado   <- sf::st_boundary(sf::st_union(estado_m))
  perimetro_vizinhos <- sf::st_boundary(sf::st_union(vizinhos_m))

  faixa_fronteira_terrestre <- sf::st_buffer(perimetro_vizinhos, TOLERANCIA_M)

  linha_costa <- sf::st_difference(perimetro_estado, faixa_fronteira_terrestre)

  if (length(linha_costa) == 0 || all(sf::st_is_empty(linha_costa))) {
    stop("Linha de costa vazia -- revisar UFs vizinhas ou tolerancia de fronteira")
  }

  sf::st_sf(geometry = linha_costa, crs = CRS_METRICO)
}

pre_processamento <- function() {
  cat("[PRE-PROCESSAMENTO] Gerando linha de costa e buffer de", BUFFER_M, "m\n")

  dados <- read_data()
  estado   <- df_para_sf(dados$estado)
  vizinhos <- df_para_sf(dados$vizinhos)

  linha_costa <- extrair_linha_costa(estado, vizinhos)
  linha_costa$comprimento_m   <- as.numeric(sf::st_length(linha_costa))
  linha_costa$dt_processamento <- Sys.Date()

  buffer_5km <- sf::st_sf(
    geometry       = sf::st_union(sf::st_buffer(sf::st_geometry(linha_costa), BUFFER_M)),
    buffer_m       = BUFFER_M,
    dt_processamento = Sys.Date()
  )

  cat("[PRE-PROCESSAMENTO] Linha de costa: comprimento total",
      round(sum(linha_costa$comprimento_m) / 1000, 1), "km\n")
  cat("[PRE-PROCESSAMENTO] Buffer de", BUFFER_M, "m gerado\n")

  list(
    linha_costa = sf_para_df(linha_costa),
    buffer_5km  = sf_para_df(buffer_5km)
  )
}

save_data <- function(dados) {
  cat("[PRE-PROCESSAMENTO] Salvando dados no MinIO via DuckDB\n")

  tryCatch({
    timestamp <- format(Sys.time(), "%Y%m%d")
    caminhos <- character(0)

    for (nome_camada in names(dados)) {
      filepath <- sprintf(
        "silver/base_faixa_litoranea/%s/%s_%s.parquet",
        nome_camada, nome_camada, timestamp
      )

      write_parquet_to_minio(dados[[nome_camada]], filepath)

      cat("[PRE-PROCESSAMENTO] Camada salva:", filepath,
          "| registros:", nrow(dados[[nome_camada]]), "\n")
      caminhos <- c(caminhos, filepath)
    }

    return(caminhos)

  }, error = function(e) {
    cat("[PRE-PROCESSAMENTO] Erro ao salvar no MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

tryCatch({
  cat("============================================================\n")
  cat("[PRE-PROCESSAMENTO] Iniciando pre-processamento da base_faixa_litoranea...\n")
  cat("============================================================\n")

  data <- pre_processamento()
  filepath <- save_data(data)

  cat("============================================================\n")
  cat("[PRE-PROCESSAMENTO] Pre-processamento finalizado com sucesso!\n")
  cat("[PRE-PROCESSAMENTO] Arquivos:", paste(filepath, collapse = " | "), "\n")
  cat("============================================================\n")

}, error = function(e) {
  cat("[PRE-PROCESSAMENTO] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})
