#!/bin/bash

SYSTEM_PROPS="-DRABBIT_HOST=${HEALTH_HOST} -Dspring.rabbitmq.port=9672 -Dspring.zipkin.baseUrl=http://${HEALTH_HOST}:9411"

dockerComposeFile="docker-compose-${WHAT_TO_TEST}.yml"
kill_docker
docker-compose -f $dockerComposeFile kill
docker-compose -f $dockerComposeFile pull
docker-compose -f $dockerComposeFile build

if [[ "${SHOULD_START_RABBIT}" == "yes" ]] ; then
    echo -e "\n\nBooting up RabbitMQ"
    docker-compose -f $dockerComposeFile up -d rabbitmq
fi

READY_FOR_TESTS="no"
PORT_TO_CHECK=9672
echo "Waiting for RabbitMQ to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
netcat_port $PORT_TO_CHECK && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "RabbitMQ failed to start..."
    exit 1
fi

READY_FOR_TESTS="no"
PORT_TO_CHECK=2181
echo "Waiting for Zookeeper to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
docker-compose -f $dockerComposeFile up -d zookeeper
netcat_local_port $PORT_TO_CHECK && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "Zookeeper failed to start..."
    exit 1
fi

if [[ "${START_ZIPKIN}" == "true" ]]; then
    echo -e "\n\nBooting up Zipkin stuff"
    docker-compose -f $dockerComposeFile up -d

    READY_FOR_TESTS="no"
    PORT_TO_CHECK=9411
    echo -e "\n\nWaiting for Zipkin to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
    curl_health_endpoint "${PORT_TO_CHECK}" && READY_FOR_TESTS="yes"

    if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
        echo "Zipkin failed to start..."
        echo -e "\n\nPrinting docker compose logs - start\n\n"
        docker-compose -f "docker-compose-${WHAT_TO_TEST}.yml" logs || echo "Failed to print docker compose logs"
        echo -e "\n\nPrinting docker compose logs - end\n\n"
        exit 1
    fi
fi

# Boot config-server
READY_FOR_TESTS="no"
PORT_TO_CHECK=8888
echo "Waiting for the Config Server app to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
java_jar "config-server"
curl_local_health_endpoint $PORT_TO_CHECK  && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "Config server failed to start..."
    exit 1
fi

echo -e "\n\nStarting brewery apps..."
start_brewery_apps "$SYSTEM_PROPS"
