# Bibliotecas necessárias para a coleta
library(jsonlite)

# Carrega funções utilitárias
source("utils.R")

# Baixar os dados da base 
coleta <- function() {
  cat("[COLETA] Buscando dados da PokeAPI\n")

  tryCatch({
    endpoint <- "https://pokeapi.co/api/v2/pokemon?limit=50&offset=0"
    resposta <- fromJSON(endpoint)
    dados <- resposta$results

    if (is.null(dados) || nrow(dados) == 0) {
      stop("Nenhum dado retornado pela PokeAPI")
    }

    dados$id <- as.integer(gsub(".*/([0-9]+)/$", "\\1", dados$url))
    names(dados)[names(dados) == "name"] <- "nome"
    dados$data_coleta <- Sys.Date()

    dados <- dados[, c("id", "nome", "url", "data_coleta")]

    cat("[COLETA] Registros coletados:", nrow(dados), "\n")
    return(dados)

  }, error = function(e) {
    cat("[COLETA] Erro ao coletar dados:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}   

# Função para salvar no MinIO via DuckDB
save_data <- function(data) {
  cat("[COLETA] Salvando dados no MinIO via DuckDB\n")
  
  tryCatch({
    timestamp <- format(Sys.time(), "%Y%m%d")
    filepath <- sprintf("bronze/dag_template/dado/dado_%s.parquet", timestamp)

    write_parquet_to_minio(data, filepath)
    
    cat("[COLETA] Dados salvos com sucesso:", filepath, "\n")
    return(filepath)
    
  }, error = function(e) {
    cat("[COLETA] Erro ao salvar no MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# Execução principal
tryCatch({
cat("============================================================\n")
  cat("[COLETA] Coleta iniciada!\n")
  cat("============================================================\n")
  # Coleta os dados
  data <- coleta()
  
  # Salva no MinIO via DuckDB
  filepath <- save_data(data)
  
  cat("============================================================\n")
  cat("[COLETA] Coleta finalizada com sucesso!\n")
  cat("[COLETA] Arquivo:", filepath, "\n")
  cat("============================================================\n")
  
}, error = function(e) {
  cat("[COLETA] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})