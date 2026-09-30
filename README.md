# base_faixa_litoranea

Gera a linha de costa e o buffer de 5 km do Espírito Santo a partir do limite
estadual do `base_geobr`, e cruza essa faixa com as entidades reguladas pela
CVM no ES (`base_cvm`), usando as coordenadas consolidadas de geocodificação
(`base_googlemaps_cnpj`). Preenche os campos que o `base_cvm` deixa
reservados: `is_ate_5km_mar`, `distancia_mar_m` e `faixa_litoranea`.

## Estrutura do projeto

- `coleta/`: lê o limite estadual do ES (silver do `base_geobr`) e busca os
  estados vizinhos (BA, MG, RJ) via `geobr`, salvando na camada bronze.
- `pre_processamento/`: isola a linha de costa (trechos do perímetro do ES que
  não são fronteira terrestre com os vizinhos) e gera o polígono de buffer,
  na camada silver.
- `processamento/`: calcula a distância de cada entidade CVM/ES até a linha de
  costa e grava a camada gold.
- `exportacao/`: resumo por município e faixa em relação ao mar.
- `.segredos/`: deve conter arquivos e informações que não devem ser
  compartilhadas, coloque o nome da pasta no `.gitignore`.
- `utils.R`: funções compartilhadas para leitura/escrita de dados no MinIO via
  DuckDB. Vem de `dags/utils/` e é copiado pelos Dockerfiles.
- `base_faixa_litoranea.py`: DAG no Airflow.

## Fluxo base do pipeline

1. Coleta: `silver/base_geobr/malha_estado/` + estados vizinhos (`geobr`) -> bronze
2. Pré-processamento: isola a linha de costa e gera o buffer -> silver
3. Processamento: cruza com `gold/base_cvm/entidades_cvm_es/` e
   `gold/base_googlemaps_cnpj/geocodificacao_cnpj/` -> gold
4. Exportação: resumo por município e faixa em relação ao mar

## Como a linha de costa é obtida

O `geobr`/IBGE não tem uma camada dedicada de "linha de costa". Em vez de
depender de uma fonte externa nova, este domínio deriva a costa geometricamente
a partir do limite estadual que o `base_geobr` já coleta:

1. Toma o perímetro do polígono do ES (`st_boundary`).
2. Busca os polígonos dos estados vizinhos (BA, MG, RJ) diretamente via
   `geobr::read_state()`.
3. Remove do perímetro do ES os trechos que ficam a até
   `FAIXA_LITORANEA_TOLERANCIA_FRONTEIRA_M` metros do perímetro dos vizinhos
   (fronteira terrestre) — o tolerância existe porque shapefiles baixados
   separadamente para estados diferentes raramente coincidem pixel a pixel.
4. O que sobra do perímetro é a linha de costa.

Esse cálculo (e o buffer de `FAIXA_LITORANEA_BUFFER_M` metros a partir dela)
precisa de um CRS métrico, por isso a silver deste domínio trafega em CRS
projetado (`FAIXA_LITORANEA_CRS_METRICO`, padrão `31984` — SIRGAS 2000 / UTM
24S), diferente da convenção do `base_geobr` (que mantém a silver em graus,
SIRGAS 2000 geográfico). A gold é reprojetada para `FAIXA_LITORANEA_CRS_SAIDA`
(padrão `4326`), mesma convenção de saída do `base_geobr`.

## Tratamento da geometria

Mesma convenção do `base_geobr`: o parquet gravado via DuckDB não aceita o
tipo `sfc` do `sf`. Toda geometria trafega entre camadas como WKT, na coluna
`geometry_wkt`, com o CRS preservado em `crs_epsg`. Para reconstruir o objeto
espacial a jusante, use
`sf::st_as_sf(df, wkt = "geometry_wkt", crs = df$crs_epsg[1])`.

## Dependências de entrada

| Produto | Prefixo padrão no MinIO |
|---|---|
| Limite estadual do ES | `silver/base_geobr/malha_estado/` |
| Entidades CVM recortadas para o ES | `gold/base_cvm/entidades_cvm_es/` |
| Geocodificação CNPJ consolidada | `gold/base_googlemaps_cnpj/geocodificacao_cnpj/` |

Os caminhos podem ser sobrescritos, respectivamente, com:
`FAIXA_LITORANEA_GEOBR_ESTADO_PREFIX`, `CVM_ENTIDADES_ES_PREFIX`,
`GEOCODIFICACAO_CNPJ_PREFIX`.

Entidades sem geocodificação disponível ficam com
`is_ate_5km_mar`/`distancia_mar_m`/`faixa_litoranea` em branco (não são
descartadas).

## Saídas

- `gold/base_faixa_litoranea/entidades_cvm_es_litoraneo/`: entidades CVM/ES
  com `distancia_mar_m`, `is_ate_5km_mar` e `faixa_litoranea`
  (`ate_5km`/`acima_5km`) preenchidos.
- `gold/base_faixa_litoranea/linha_costa/` e
  `gold/base_faixa_litoranea/buffer_5km/`: geometrias reutilizáveis por outras
  DAGs ou para visualização, em `FAIXA_LITORANEA_CRS_SAIDA`.
- `gold/base_faixa_litoranea/resumo_municipio_faixa/`: resumo agregado.

## Parâmetros

- `FAIXA_LITORANEA_UF`: unidade federativa de referência (padrão `ES`)
- `FAIXA_LITORANEA_UFS_VIZINHAS`: estados usados para identificar a fronteira
  terrestre (padrão `BA,MG,RJ`)
- `FAIXA_LITORANEA_GEOBR_ANO`: ano da malha dos vizinhos via `geobr` (padrão
  `2020`, mesmo ano usado pelo `base_geobr` para o ES — anos diferentes podem
  gerar desalinhamento entre os polígonos)
- `FAIXA_LITORANEA_GEOBR_ESTADO_CRS`: CRS de fallback ao ler a malha do ES,
  caso a coluna `crs_epsg` esteja ausente (padrão `4674`)
- `FAIXA_LITORANEA_CRS_METRICO`: CRS métrico usado para buffer/distância
  (padrão `31984`, SIRGAS 2000 / UTM 24S)
- `FAIXA_LITORANEA_CRS_SAIDA`: CRS de saída na gold (padrão `4326`)
- `FAIXA_LITORANEA_TOLERANCIA_FRONTEIRA_M`: tolerância, em metros, para
  considerar um trecho do perímetro como fronteira terrestre (padrão `500`)
- `FAIXA_LITORANEA_BUFFER_M`: distância do buffer a partir da costa (padrão
  `5000`)

## Pontos de atenção

- Depende de `sf`, que compila contra GDAL, GEOS e PROJ; o primeiro build leva
  minutos por imagem (mesma observação do `base_geobr`).
- A DAG usa `ExternalTaskSensor` apontando para tasks de `base_geobr`,
  `base_cvm` e `base_googlemaps_cnpj`; nomes divergentes deixam os sensores em
  espera até o timeout de seis horas.
- Se o ano da malha dos vizinhos (`FAIXA_LITORANEA_GEOBR_ANO`) divergir do ano
  usado pelo `base_geobr` para o limite do ES, os polígonos podem não alinhar
  bem na fronteira, distorcendo a linha de costa perto das divisas.
- `FAIXA_LITORANEA_TOLERANCIA_FRONTEIRA_M` muito baixo pode deixar resíduos de
  fronteira terrestre classificados como costa (e vice-versa se for alto
  demais); 500 m é um ponto de partida, não um valor validado em campo.
