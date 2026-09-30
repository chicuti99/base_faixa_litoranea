# Bibliotecas necessárias para a base

# Carrega funções utilitárias
source("utils.R")

processamento <- function(){
  cat("[PROCESSAMENTO] Aplicando processamento final dos dados\n")

  data <- read_data()

  if (is.null(data) || nrow(data) == 0) {
    stop("Base de entrada vazia para processamento")
  }

  colunas_esperadas <- c("id", "geracao", "data_coleta", "dt_processamento")
  faltantes <- setdiff(colunas_esperadas, names(data))
  if (length(faltantes) > 0) {
    stop(sprintf("Colunas ausentes na base de entrada: %s", paste(faltantes, collapse = ", ")))
  }

  data$id <- as.integer(data$id)
  data$data_coleta <- as.Date(data$data_coleta)
  data$dt_processamento <- as.Date(data$dt_processamento)
  data$geracao <- as.character(data$geracao)

  data <- data[!is.na(data$id) & !is.na(data$geracao), ]

  if (nrow(data) == 0) {
    stop("Não há registros válidos para processamento final")
  }

  total_registros <- nrow(data)

  resumo <- aggregate(
    id ~ geracao,
    data = data,
    FUN = length
  )

  names(resumo)[names(resumo) == "id"] <- "qtd_pokemons"

  id_min <- aggregate(id ~ geracao, data = data, FUN = min)
  names(id_min)[2] <- "id_min"

  id_max <- aggregate(id ~ geracao, data = data, FUN = max)
  names(id_max)[2] <- "id_max"

  resumo <- merge(resumo, id_min, by = "geracao", all.x = TRUE)
  resumo <- merge(resumo, id_max, by = "geracao", all.x = TRUE)

  resumo$percentual <- round((resumo$qtd_pokemons / total_registros) * 100, 2)
  resumo$data_referencia <- max(data$data_coleta, na.rm = TRUE)
  resumo$dt_processamento <- Sys.Date()

  resumo <- resumo[order(resumo$geracao), ]
  resumo <- resumo[, c("geracao", "qtd_pokemons", "percentual", "id_min", "id_max", "data_referencia", "dt_processamento")]

  cat("[PROCESSAMENTO] Linhas geradas na camada gold:", nrow(resumo), "\n")
  return(resumo)
}

# Função para salvar no MinIO via DuckDB
save_data <- function(data) {
  cat("[PROCESSAMENTO] Salvando dados no MinIO via DuckDB\n")
  
  tryCatch({
    timestamp <- format(Sys.time(), "%Y%m%d")
    filepath <- sprintf("gold/dag_template/dado/dado_%s.parquet", timestamp)

    write_parquet_to_minio(data, filepath)
    
    cat("[PROCESSAMENTO] Dados salvos com sucesso:", filepath, "\n")
    return(filepath)
    
  }, error = function(e) {
    cat("[PROCESSAMENTO] Erro ao salvar no MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

read_data <- function() {
  cat("[PROCESSAMENTO] Lendo dados do MinIO via DuckDB\n")
  
  tryCatch({
    data <- read_latest_parquet_from_minio("silver/dag_template/dado/")

    # Ou se preferir ler um arquivo específico:
    # data <- read_parquet_from_minio("silver/dag_template/dado/dado_20240601.parquet")

    if (is.null(data) || nrow(data) == 0) {
      stop("Nenhum arquivo/dado encontrado em silver/dag_template/dado/")
    }

    cat("[PROCESSAMENTO] Dados lidos com sucesso. Registros:", nrow(data), "\n")
    return(data)
    
  }, error = function(e) {
    cat("[PROCESSAMENTO] Erro ao ler do MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# Execução principal
tryCatch({
  cat("============================================================\n")
  cat("[PROCESSAMENTO] Iniciando processamento dos dados da Base X...\n")
  cat("============================================================\n")
  
  # Pré-processa os dados coletados
  data <- processamento()

  # Salva no MinIO via DuckDB
  filepath <- save_data(data)
  
  cat("============================================================\n")
  cat("[PROCESSAMENTO] Processamento finalizado com sucesso!\n")
  cat("[PROCESSAMENTO] Arquivo:", filepath, "\n")
  cat("============================================================\n")
  
}, error = function(e) {
  cat("[PROCESSAMENTO] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})
