from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sensors.external_task import ExternalTaskSensor
import os

# Configurações padrão
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2023, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Rede Docker (variável de ambiente do .env)
docker_network = os.getenv('DOCKER_NETWORK')

# Parâmetros do domínio, repassados aos containers.
faixa_litoranea_env = {
    'FAIXA_LITORANEA_UF': os.getenv('FAIXA_LITORANEA_UF', 'ES'),
    'FAIXA_LITORANEA_UFS_VIZINHAS': os.getenv('FAIXA_LITORANEA_UFS_VIZINHAS', 'BA,MG,RJ'),
    'FAIXA_LITORANEA_GEOBR_ANO': os.getenv('FAIXA_LITORANEA_GEOBR_ANO', '2020'),
    'FAIXA_LITORANEA_GEOBR_ESTADO_PREFIX': os.getenv(
        'FAIXA_LITORANEA_GEOBR_ESTADO_PREFIX', 'silver/base_geobr/malha_estado/'
    ),
    'FAIXA_LITORANEA_GEOBR_ESTADO_CRS': os.getenv('FAIXA_LITORANEA_GEOBR_ESTADO_CRS', '4674'),
    'FAIXA_LITORANEA_CRS_METRICO': os.getenv('FAIXA_LITORANEA_CRS_METRICO', '31984'),
    'FAIXA_LITORANEA_CRS_SAIDA': os.getenv('FAIXA_LITORANEA_CRS_SAIDA', '4326'),
    'FAIXA_LITORANEA_TOLERANCIA_FRONTEIRA_M': os.getenv('FAIXA_LITORANEA_TOLERANCIA_FRONTEIRA_M', '500'),
    'FAIXA_LITORANEA_BUFFER_M': os.getenv('FAIXA_LITORANEA_BUFFER_M', '5000'),
    'CVM_ENTIDADES_ES_PREFIX': os.getenv('CVM_ENTIDADES_ES_PREFIX', 'gold/base_cvm/entidades_cvm_es/'),
    'GEOCODIFICACAO_CNPJ_PREFIX': os.getenv(
        'GEOCODIFICACAO_CNPJ_PREFIX', 'gold/base_googlemaps_cnpj/geocodificacao_cnpj/'
    ),
}

# Define o DAG
with DAG(
    'base_faixa_litoranea',
    default_args=default_args,
    description=(
        'DAG para gerar a linha de costa/buffer de 5km do ES e calcular a '
        'distancia ate o mar das entidades CVM (base_cvm)'
    ),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=['base_faixa_litoranea', 'geoespacial', 'cvm', 'litoral'],
) as dag:

    # Sensores de dependencia externa: aguarda a atualizacao mais recente das
    # tasks das quais este dominio depende.
    # ATENCAO: ajustar external_dag_id/external_task_id se os nomes finais
    # dessas DAGs forem diferentes -- nomes divergentes deixam os sensores em
    # espera ate o timeout de seis horas, sem erro explicito.
    aguarda_geobr = ExternalTaskSensor(
        task_id='aguarda_geobr',
        external_dag_id='base_geobr',
        external_task_id='pre_processamento',
        allowed_states=['success'],
        mode='reschedule',
        timeout=60 * 60 * 6,
        poke_interval=300,
    )

    aguarda_cvm = ExternalTaskSensor(
        task_id='aguarda_cvm',
        external_dag_id='base_cvm',
        external_task_id='processamento',
        allowed_states=['success'],
        mode='reschedule',
        timeout=60 * 60 * 6,
        poke_interval=300,
    )

    aguarda_googlemaps_cnpj = ExternalTaskSensor(
        task_id='aguarda_googlemaps_cnpj',
        external_dag_id='base_googlemaps_cnpj',
        external_task_id='processamento',
        allowed_states=['success'],
        mode='reschedule',
        timeout=60 * 60 * 6,
        poke_interval=300,
    )

    coleta = DockerOperator(
        task_id='coleta',
        image='base_faixa_litoranea-coleta:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
        environment=faixa_litoranea_env,
        execution_timeout=timedelta(minutes=30),
    )

    pre_processamento = DockerOperator(
        task_id='pre_processamento',
        image='base_faixa_litoranea-pre_processamento:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
        environment=faixa_litoranea_env,
        execution_timeout=timedelta(minutes=30),
    )

    processamento = DockerOperator(
        task_id='processamento',
        image='base_faixa_litoranea-processamento:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
        environment=faixa_litoranea_env,
        execution_timeout=timedelta(minutes=30),
    )

    exportacao = DockerOperator(
        task_id='exportacao',
        image='base_faixa_litoranea-exportacao:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
    )

    # Define ordem de execução
    [aguarda_geobr, aguarda_cvm, aguarda_googlemaps_cnpj] >> coleta >> pre_processamento >> processamento >> exportacao
