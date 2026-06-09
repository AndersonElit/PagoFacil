package com.integrationservice.sagacamel;

import com.integrationservice.model.SagaCoordinatorPort;
import org.apache.camel.ProducerTemplate;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.util.UUID;

/** Implementa SagaCoordinatorPort delegando en las rutas Camel Saga (respaldadas por LRA). */
@Component
public class CamelSagaCoordinatorAdapter implements SagaCoordinatorPort {

    private final ProducerTemplate producerTemplate;

    public CamelSagaCoordinatorAdapter(ProducerTemplate producerTemplate) {
        this.producerTemplate = producerTemplate;
    }

    @Override
    public Mono<String> begin(String sagaType, Object payload) {
        String sagaId = UUID.randomUUID().toString();
        return Mono.fromRunnable(() ->
                producerTemplate.sendBodyAndHeader("direct:saga-" + sagaType, payload, "sagaId", sagaId))
                .thenReturn(sagaId);
    }

    @Override
    public Mono<Void> complete(String sagaId) {
        return Mono.empty();
    }

    @Override
    public Mono<Void> compensate(String sagaId) {
        return Mono.fromRunnable(() ->
                producerTemplate.sendBodyAndHeader("direct:compensar-deposit", null, "sagaId", sagaId))
                .then();
    }
}
