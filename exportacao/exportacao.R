# Bibliotecas necessárias para a base

# Carrega funções utilitárias
source("utils.R")

exportacao <- function(){
  cat("[EXPORTACAO] Gerando dataviz da camada gold\n")

  data <- read_data()

  if (is.null(data) || nrow(data) == 0) {
    stop("Base de entrada vazia para exportação")
  }

  colunas_esperadas <- c("geracao", "qtd_pokemons")
  faltantes <- setdiff(colunas_esperadas, names(data))
  if (length(faltantes) > 0) {
    stop(sprintf("Colunas ausentes na base de entrada: %s", paste(faltantes, collapse = ", ")))
  }

  resumo <- aggregate(qtd_pokemons ~ geracao, data = data, FUN = sum)
  resumo <- resumo[order(resumo$geracao), ]

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  output_file <- sprintf("/tmp/pokemons_por_geracao_%s.png", timestamp)

  png(filename = output_file, width = 1200, height = 700, res = 120)
  barplot(
    height = resumo$qtd_pokemons,
    names.arg = resumo$geracao,
    main = "Quantidade de Pokémons por Geração",
    xlab = "Geração",
    ylab = "Quantidade",
    las = 2,
    col = "gray40",
    border = "white"
  )
  dev.off()

  cat("[EXPORTACAO] Dataviz gerado com sucesso em:", output_file, "\n")
  return(output_file)
}

save_data <- function(local_file) {
  cat("[EXPORTACAO] Salvando dataviz\n")

  tryCatch({
    # Coloque aqui a lógica para salvar o arquivo local_file em um destino final, 
    # como um arquivo local, uma API, etc.

    return(local_file)
  }, error = function(e) {
    cat("[EXPORTACAO] Erro ao salvar arquivo local:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

read_data <- function() {
  cat("[EXPORTACAO] Lendo dados do MinIO via DuckDB\n")
  
  tryCatch({
    data <- read_latest_parquet_from_minio("gold/dag_template/dado/")

    # Ou se preferir ler um arquivo específico:
    # data <- read_parquet_from_minio("gold/dag_template/dado/dado_20240601.parquet")

    if (is.null(data) || nrow(data) == 0) {
      stop("Nenhum arquivo/dado encontrado em gold/dag_template/dado/")
    }

    cat("[EXPORTACAO] Dados lidos com sucesso. Registros:", nrow(data), "\n")
    return(data)
    
  }, error = function(e) {
    cat("[EXPORTACAO] Erro ao ler do MinIO:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# Execução principal
tryCatch({
  cat("============================================================\n")
  cat("[EXPORTACAO] Iniciando exportação dos dados da Base X...\n")
  cat("============================================================\n")
  
  # Gera visualização
  output_file <- exportacao()

  # Salva arquivo da visualização
  filepath <- save_data(output_file)
  
  cat("============================================================\n")
  cat("[EXPORTACAO] Exportação finalizada com sucesso!\n")
  cat("[EXPORTACAO] Arquivo:", filepath, "\n")
  cat("============================================================\n")
  
}, error = function(e) {
  cat("[EXPORTACAO] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})
