FROM confluentinc/cp-kafka-connect:7.6.0

RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:2.5.4 && \
    confluent-hub install --no-prompt confluentinc/kafka-connect-s3:10.5.4