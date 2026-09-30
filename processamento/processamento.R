#!/usr/bin/env Rscript

# Dominio: base_faixa_litoranea
# Descricao: cruza a linha de costa/buffer (silver) com as entidades CVM no
#            ES (gold do base_cvm), usando as coordenadas consolidadas de
#            geocodificacao (gold do base_googlemaps_cnpj), para calcular a
#            distancia ate o mar e preencher is_ate_5km_mar/distancia_mar_m/
#            faixa_litoranea -- campos que o base_cvm deixa reservados.
#            Tambem republica a linha de costa e o buffer em CRS geografico
#            (mesma convencao de saida do base_geobr) para reuso/visualizacao.

library(sf)

source("utils.R")

valor_ambiente <- function(nome, padrao) {
  valor <- Sys.getenv(nome, unset = "")
  if (nzchar(valor)) valor else padrao
}

texto_sem_na <- function(valor) {
  valor <- trimws(as.character(valor))
  valor[is.na(valor) | valor == "NA"] <- ""
  valor
}

CRS_METRICO <- as.integer(valor_ambiente("FAIXA_LITORANEA_CRS_METRICO", "31984"))
CRS_SAIDA   <- as.integer(valor_ambiente("FAIXA_LITORANEA_CRS_SAIDA", "4326"))
BUFFER_M    <- as.numeric(valor_ambiente("FAIXA_LITORANEA_BUFFER_M", "5000"))

CVM_ENTIDADES_ES_PREFIX     <- valor_ambiente("CVM_ENTIDADES_ES_PREFIX", "gold/base_cvm/entidades_cvm_es/")
GEOCODIFICACAO_CNPJ_PREFIX  <- valor_ambiente("GEOCODIFICACAO_CNPJ_PREFIX", "gold/base_googlemaps_cnpj/geocodificacao_cnpj/")

df_para_sf <- function(df) {
  crs <- if ("crs_epsg" %in% names(df) && !is.na(df$crs_epsg[1])) df$crs_epsg[1] else CRS_METRICO
  sf::st_as_sf(df, wkt = "geometry_wkt", crs = crs)
}

sf_para_df <- function(obj) {
  df <- sf::st_drop_geometry(obj)
  df$geometry_wkt <- sf::st_as_text(sf::st_geometry(obj))
  df$crs_epsg     <- sf::st_crs(obj)$epsg
  return(df)
}

read_data <- function() {
  cat("[PROCESSAMENTO] Lendo dados do MinIO via DuckDB\n")

  tryCatch({
    linha_costa <- read_latest_parquet_from_minio("silver/base_faixa_litoranea/linha_costa/")
    entidades   <- read_latest_parquet_from_minio(CVM_ENTIDADES_ES_PREFIX)
    geocod      <- read_latest_parquet_from_minio(GEOCODIFICACAO_CNPJ_PREFIX)

    if (is.null(linha_costa) || nrow(linha_costa) == 0) {
      stop("Base de entrada vazia: silver/base_faixa_litoranea/linha_costa/")
    }
    if (is.null(entidades) || nrow(entidades) == 0) {
      stop(sprintf("Base de entrada vazia: %s", CVM_ENTIDADES_ES_PREFIX))
    }
    if (is.null(geocod) || nrow(geocod) == 0) {
      stop(sprintf("Base de entrada vazia: %s", GEOCODIFICACAO_CNPJ_PREFIX))
    }

    cat("[PROCESSAMENTO] Linha de costa lida\n")
    cat("[PROCESSAMENTO] Entidades CVM/ES lidas:", nrow(entidades), "\n")
    cat("[PROCESSAMENTO] Geocodificacoes lidas:", nrow(geocod), "\n")

    return(list(linha_costa = linha_costa, entidades = entidades, geocod = geocod))

  }, error = function(e) {
    cat("[PROCESSAMENTO] Erro ao ler do MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

calcular_distancia_mar <- function(entidades, geocod, linha_costa_m) {
  if (!"cnpj" %in% names(entidades)) {
    stop("Gold/entidades_cvm_es nao possui coluna cnpj")
  }
  if (!all(c("cnpj", "lat", "lon") %in% names(geocod))) {
    stop("Gold/geocodificacao_cnpj nao possui colunas cnpj/lat/lon")
  }

  geocod <- geocod[!duplicated(geocod$cnpj), c("cnpj", "lat", "lon")]
  base <- merge(entidades, geocod, by = "cnpj", all.x = TRUE)

  tem_coordenada <- !is.na(base$lat) & !is.na(base$lon)
  base$distancia_mar_m  <- NA_real_
  base$is_ate_5km_mar   <- NA
  base$faixa_litoranea  <- NA_character_

  if (any(tem_coordenada)) {
    pontos <- sf::st_as_sf(
      base[tem_coordenada, ],
      coords = c("lon", "lat"),
      crs = 4326,
      remove = FALSE
    )
    pontos_m <- sf::st_transform(pontos, CRS_METRICO)

    # linha_costa_m tem uma unica feature, entao st_distance retorna uma
    # matriz Nx1; as.numeric() a achata na mesma ordem dos pontos.
    distancias <- as.numeric(sf::st_distance(pontos_m, linha_costa_m))

    base$distancia_mar_m[tem_coordenada] <- distancias
    base$is_ate_5km_mar[tem_coordenada]  <- distancias <= BUFFER_M
    base$faixa_litoranea[tem_coordenada] <- ifelse(
      distancias <= BUFFER_M, "ate_5km", "acima_5km"
    )
  }

  cat("[PROCESSAMENTO] Entidades com coordenada:", sum(tem_coordenada), "de", nrow(base), "\n")
  cat("[PROCESSAMENTO] Entidades na faixa litoranea (<=", BUFFER_M, "m):",
      sum(base$is_ate_5km_mar, na.rm = TRUE), "\n")

  base
}

processamento <- function() {
  cat("[PROCESSAMENTO] Calculando distancia ate a linha de costa\n")

  dados <- read_data()
  linha_costa <- df_para_sf(dados$linha_costa)
  linha_costa_m <- sf::st_transform(linha_costa, CRS_METRICO)

  entidades_litoraneo <- calcular_distancia_mar(dados$entidades, dados$geocod, linha_costa_m)
  entidades_litoraneo$dt_processamento <- Sys.Date()

  linha_costa_saida <- sf::st_transform(linha_costa, CRS_SAIDA)
  linha_costa_saida$dt_processamento <- Sys.Date()

  buffer_saida <- sf::st_sf(
    geometry = sf::st_transform(sf::st_geometry(linha_costa_m) |> sf::st_buffer(BUFFER_M) |> sf::st_union(), CRS_SAIDA),
    buffer_m = BUFFER_M,
    dt_processamento = Sys.Date()
  )

  list(
    entidades_cvm_es_litoraneo = entidades_litoraneo,
    linha_costa = sf_para_df(linha_costa_saida),
    buffer_5km  = sf_para_df(buffer_saida)
  )
}

save_data <- function(dados) {
  cat("[PROCESSAMENTO] Salvando dados no MinIO via DuckDB\n")

  tryCatch({
    timestamp <- format(Sys.time(), "%Y%m%d")
    caminhos <- character(0)

    for (nome_camada in names(dados)) {
      filepath <- sprintf(
        "gold/base_faixa_litoranea/%s/%s_%s.parquet",
        nome_camada, nome_camada, timestamp
      )

      write_parquet_to_minio(dados[[nome_camada]], filepath)

      cat("[PROCESSAMENTO] Camada salva:", filepath,
          "| registros:", nrow(dados[[nome_camada]]), "\n")
      caminhos <- c(caminhos, filepath)
    }

    return(caminhos)

  }, error = function(e) {
    cat("[PROCESSAMENTO] Erro ao salvar no MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

tryCatch({
  cat("============================================================\n")
  cat("[PROCESSAMENTO] Iniciando processamento da base_faixa_litoranea...\n")
  cat("============================================================\n")

  data <- processamento()
  filepath <- save_data(data)

  cat("============================================================\n")
  cat("[PROCESSAMENTO] Processamento finalizado com sucesso!\n")
  cat("[PROCESSAMENTO] Arquivos:", paste(filepath, collapse = " | "), "\n")
  cat("============================================================\n")

}, error = function(e) {
  cat("[PROCESSAMENTO] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})
