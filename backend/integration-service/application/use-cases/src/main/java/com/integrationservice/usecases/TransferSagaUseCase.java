package com.integrationservice.usecases;

import com.integrationservice.model.SagaCoordinatorPort;
import reactor.core.publisher.Mono;

/**
 * Orquesta la saga 'transfer'. Define la intención de negocio; la secuencia de pasos y
 * compensaciones se materializa en la ruta Camel Saga del adaptador. No conoce Camel ni LRA.
 */
public class TransferSagaUseCase {

    private final SagaCoordinatorPort coordinator;

    public TransferSagaUseCase(SagaCoordinatorPort coordinator) {
        this.coordinator = coordinator;
    }

    public Mono<String> ejecutar(Object payload) {
        return coordinator.begin("transfer", payload);
    }
}
