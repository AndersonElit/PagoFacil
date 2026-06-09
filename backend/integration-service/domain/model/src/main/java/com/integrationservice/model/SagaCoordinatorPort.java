package com.integrationservice.model;

import reactor.core.publisher.Mono;

/** Puerto secundario de coordinación de saga (implementado por el adaptador Camel/LRA). */
public interface SagaCoordinatorPort {
    Mono<String> begin(String sagaType, Object payload);
    Mono<Void> complete(String sagaId);
    Mono<Void> compensate(String sagaId);
}
