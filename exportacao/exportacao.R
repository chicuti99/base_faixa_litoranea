#!/usr/bin/env Rscript

# Dominio: base_faixa_litoranea
# Descricao: resumo de entidades CVM/ES por municipio e faixa em relacao ao
#            mar (mesmo padrao de exportacao do base_cvm/base_fazenda_cnpj:
#            uma tabela agregada na gold, nao um artefato visual).

source("utils.R")

texto_sem_na <- function(valor) {
  valor <- trimws(as.character(valor))
  valor[is.na(valor) | valor == "NA"] <- ""
  valor
}

read_data <- function() {
  dados <- read_latest_parquet_from_minio("gold/base_faixa_litoranea/entidades_cvm_es_litoraneo/")
  if (is.null(dados) || nrow(dados) == 0) {
    stop("Gold vazio: gold/base_faixa_litoranea/entidades_cvm_es_litoraneo/")
  }
  dados
}

exportacao <- function() {
  cat("[EXPORTACAO] Gerando resumo da faixa litoranea por municipio\n")
  entidades <- read_data()

  colunas <- c("municipio_referencia", "faixa_litoranea", "cnpj")
  faltantes <- setdiff(colunas, names(entidades))
  if (length(faltantes) > 0) {
    stop(sprintf(
      "Gold/entidades_cvm_es_litoraneo: colunas ausentes: %s",
      paste(faltantes, collapse = ", ")
    ))
  }

  entidades$municipio_referencia <- texto_sem_na(entidades$municipio_referencia)
  entidades$faixa_litoranea <- ifelse(
    texto_sem_na(entidades$faixa_litoranea) == "", "sem_coordenada", entidades$faixa_litoranea
  )

  resumo <- aggregate(
    cnpj ~ municipio_referencia + faixa_litoranea,
    data = entidades,
    FUN = length
  )
  names(resumo)[names(resumo) == "cnpj"] <- "qtd_entidades"

  distancia_media <- aggregate(
    distancia_mar_m ~ municipio_referencia + faixa_litoranea,
    data = entidades,
    FUN = function(x) round(mean(x, na.rm = TRUE), 1)
  )
  names(distancia_media)[names(distancia_media) == "distancia_mar_m"] <- "distancia_mar_media_m"

  resumo <- merge(resumo, distancia_media, by = c("municipio_referencia", "faixa_litoranea"), all.x = TRUE)
  resumo$data_exportacao <- Sys.Date()
  resumo <- resumo[order(resumo$municipio_referencia, resumo$faixa_litoranea), ]

  cat("[EXPORTACAO] Linhas no resumo:", nrow(resumo), "\n")
  resumo
}

save_data <- function(dados) {
  caminho <- sprintf(
    "gold/base_faixa_litoranea/resumo_municipio_faixa/resumo_municipio_faixa_%s.parquet",
    format(Sys.time(), "%Y%m%d")
  )
  write_parquet_to_minio(dados, caminho)
  cat("[EXPORTACAO] Salvo:", caminho, "\n")
  caminho
}

tryCatch({
  cat("============================================================\n")
  cat("[EXPORTACAO] Iniciando base_faixa_litoranea\n")
  cat("============================================================\n")

  dados <- exportacao()
  caminho <- save_data(dados)

  cat("============================================================\n")
  cat("[EXPORTACAO] Finalizada com sucesso\n")
  cat("[EXPORTACAO] Arquivo:", caminho, "\n")
  cat("============================================================\n")
}, error = function(e) {
  cat("[EXPORTACAO] Erro fatal:", conditionMessage(e), "\n")
  quit(status = 1)
})
