package com.integrationservice.usecases;

import com.integrationservice.model.SagaCoordinatorPort;
import reactor.core.publisher.Mono;

/**
 * Orquesta la saga 'withdrawal'. Define la intención de negocio; la secuencia de pasos y
 * compensaciones se materializa en la ruta Camel Saga del adaptador. No conoce Camel ni LRA.
 */
public class WithdrawalSagaUseCase {

    private final SagaCoordinatorPort coordinator;

    public WithdrawalSagaUseCase(SagaCoordinatorPort coordinator) {
        this.coordinator = coordinator;
    }

    public Mono<String> ejecutar(Object payload) {
        return coordinator.begin("withdrawal", payload);
    }
}
