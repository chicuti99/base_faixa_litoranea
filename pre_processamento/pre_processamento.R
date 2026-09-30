# Bibliotecas necessárias para a base

# Carrega funções utilitárias
source("utils.R")

pre_processamento <- function(){
  cat("[PRE-PROCESSAMENTO] Aplicando transformações nos dados\n")

  data <- read_data()

  if (is.null(data) || nrow(data) == 0) {
    stop("Base de entrada vazia para pré-processamento")
  }

  colunas_esperadas <- c("id", "nome", "url", "data_coleta")
  faltantes <- setdiff(colunas_esperadas, names(data))
  if (length(faltantes) > 0) {
    stop(sprintf("Colunas ausentes na base de entrada: %s", paste(faltantes, collapse = ", ")))
  }

  data$id <- as.integer(data$id)
  data$nome <- trimws(tolower(data$nome))
  data$nome <- iconv(data$nome, from = "UTF-8", to = "ASCII//TRANSLIT")
  data$nome <- gsub("[^a-z0-9]+", "_", data$nome)
  data$nome <- gsub("(^_|_$)", "", data$nome)
  data$url <- trimws(data$url)
  data$data_coleta <- as.Date(data$data_coleta)

  data <- data[!is.na(data$id) & !is.na(data$nome) & nzchar(data$nome), ]
  data <- data[order(data$id), ]
  data <- data[!duplicated(data$id), ]

  data$geracao <- cut(
    data$id,
    breaks = c(0, 151, 251, 386, 493, 649, 721, 809, 905, Inf),
    labels = c("geracao_1", "geracao_2", "geracao_3", "geracao_4", "geracao_5", "geracao_6", "geracao_7", "geracao_8", "geracao_9"),
    right = TRUE
  )

  data$nome_exibicao <- gsub("_", " ", data$nome)
  data$nome_exibicao <- tools::toTitleCase(data$nome_exibicao)

  data$dt_processamento <- Sys.Date()

  data <- data[, c("id", "nome", "nome_exibicao", "geracao", "url", "data_coleta", "dt_processamento")]

  cat("[PRE-PROCESSAMENTO] Registros após limpeza:", nrow(data), "\n")
  return(data)
}

# Função para salvar no MinIO via DuckDB
save_data <- function(data) {
  cat("[PRE-PROCESSAMENTO] Salvando dados no MinIO via DuckDB\n")
  
  tryCatch({
    timestamp <- format(Sys.time(), "%Y%m%d")
    filepath <- sprintf("silver/dag_template/dado/dado_%s.parquet", timestamp)

    write_parquet_to_minio(data, filepath)
    
    cat("[PRE-PROCESSAMENTO] Dados salvos com sucesso:", filepath, "\n")
    return(filepath)
    
  }, error = function(e) {
    cat("[PRE-PROCESSAMENTO] Erro ao salvar no MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

read_data <- function() {
  cat("[PRE-PROCESSAMENTO] Lendo dados do MinIO via DuckDB\n")
  
  tryCatch({
    data <- read_latest_parquet_from_minio("bronze/dag_template/dado/")

    # Ou se preferir ler um arquivo específico:
    # data <- read_parquet_from_minio("bronze/dag_template/dado/dado_20240601.parquet")

    cat("[PRE-PROCESSAMENTO] Dados lidos com sucesso. Registros:", nrow(data), "\n")
    return(data)
    
  }, error = function(e) {
    cat("[PRE-PROCESSAMENTO] Erro ao ler do MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# Execução principal
tryCatch({
  cat("============================================================\n")
  cat("[PRE-PROCESSAMENTO] Iniciando pré-processamento dos dados da Base X...\n")
  cat("============================================================\n")
  
  # Pré-processa os dados coletados
  data <- pre_processamento()

  # Salva no MinIO via DuckDB
  filepath <- save_data(data)
  
  cat("============================================================\n")
  cat("[PRE-PROCESSAMENTO] Pré-processamento finalizado com sucesso!\n")
  cat("[PRE-PROCESSAMENTO] Arquivo:", filepath, "\n")
  cat("============================================================\n")
  
}, error = function(e) {
  cat("[PRE-PROCESSAMENTO] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})
