package com.integrationservice;

import com.integrationservice.model.SagaCoordinatorPort;
import com.integrationservice.usecases.DepositSagaUseCase;
import com.integrationservice.usecases.TransferSagaUseCase;
import com.integrationservice.usecases.WithdrawalSagaUseCase;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Expone los casos de uso (dominio limpio de Spring) como beans, inyectando los puertos. */
@Configuration
public class UseCasesConfig {

    @Bean
    public DepositSagaUseCase depositSagaUseCase(SagaCoordinatorPort coordinator) {
        return new DepositSagaUseCase(coordinator);
    }

    @Bean
    public TransferSagaUseCase transferSagaUseCase(SagaCoordinatorPort coordinator) {
        return new TransferSagaUseCase(coordinator);
    }

    @Bean
    public WithdrawalSagaUseCase withdrawalSagaUseCase(SagaCoordinatorPort coordinator) {
        return new WithdrawalSagaUseCase(coordinator);
    }
}
