from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.docker.operators.docker import DockerOperator
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

# Define o DAG
with DAG(
    'dag_template',
    default_args=default_args,
    description='DAG para coleta, processamento e visualização da base x',
    schedule='@daily',
    catchup=False,
    tags=['dag_template', 'x', 'tag'],
) as dag:

    coleta = DockerOperator(
        task_id='coleta',
        image='dag_template-coleta:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
    )
    
    pre_processamento = DockerOperator(
        task_id='pre_processamento',
        image='dag_template-pre_processamento:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
    )

    processamento = DockerOperator(
        task_id='processamento',
        image='dag_template-processamento:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
    )

    exportacao = DockerOperator(
        task_id='exportacao',
        image='dag_template-exportacao:latest',
        api_version='auto',
        auto_remove='success',
        docker_url='unix://var/run/docker.sock',
        network_mode=docker_network,
        mount_tmp_dir=False,
    )

    # Define ordem de execução
    coleta >> pre_processamento >>processamento >> exportacao