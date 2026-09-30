# DAG Template

Template base para pipelines de dados em camadas, com etapas separadas por responsabilidade.

## Estrutura do projeto

- `coleta/`: extrai dados da fonte externa e salva na camada bronze.
- `pre_processamento/`: limpa e padroniza os dados da bronze para a camada silver.
- `processamento/`: aplica regras finais e agregações para gerar a camada gold.
- `exportacao/`: consome a gold e gera saídas finais (ex.: visualização PNG).
- `.segredos/`: deve conter arquivos e informações que não devem ser compartilhadas, coloque o nome da pasta no .gitignore. Exemplo é a chave ssh para exportação de dados.
- `utils.R`: funções compartilhadas para leitura/escrita de dados no MinIO via DuckDB.
- `dag_template.py`: script auxiliar para criação de uma DAG no Airflow.

## Fluxo base do pipeline

1. Coleta: fonte externa -> bronze
2. Pré-processamento: bronze -> silver
3. Processamento: silver -> gold
4. Exportação: gold -> artefato final (arquivo local)

## Convenção de camadas

- Bronze: dado bruto da origem
- Silver: dado tratado e padronizado
- Gold: dado consolidado para consumo
